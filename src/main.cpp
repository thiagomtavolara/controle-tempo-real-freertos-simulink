/*
 * Infraestrutura de controle da planta didatica HVAC.
 * Autor: Thiago Miorando Tavolara
 * TCC em Engenharia de Controle e Automacao - UFRGS
 * Orientacao: Prof. Marcelo Gotz
 *
 * Responsabilidades: adquirir temperatura, executar o controlador gerado
 * pelo Simulink, acionar lampada/cooler e comunicar com a GUI MATLAB.
 * Modos: 0 = malha aberta; 1 = controlador Simulink.
 * A lei de controle e desenvolvida no Simulink e integrada pelo importador.
 */
#include <Arduino.h>
#include <Arduino_FreeRTOS.h>
#include <Wire.h>
#include <avr/wdt.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "ponte_simulink.h"
#include "transacao.h"
#define SAMPLE_PERIOD_MS 200 // Periodo nominal; manter igual ao Ts do modelo/importador.
#define SHT20_ADDR 0x40
#define SHT20_TRIGGER_T_NOHOLD 0xF3
#define SHT20_MAX_CONVERSION_MS 85
#define PIN_LAMPADA_PWM 5
#define PIN_LAMPADA_DIR 6
#define PIN_COOLER_PWM 9
#define PIN_COOLER_DIR 10
// Reservas de pilha das tarefas; revisar ao ampliar suas responsabilidades.
#define STACK_SENSOR 112
#define STACK_CONTROL 160
#define STACK_SERIAL 192

// Dados compartilhados: leitura e escrita agrupadas em secoes criticas.
// volatile nao substitui a protecao de acesso entre as tarefas.
// Temperatura/referencia em graus Celsius; comandos nominais em volts.
volatile float temperatura=NAN, referencia=25, cooler=0, aplicado=0, manual=0;
volatile uint8_t modo=0;
// A telemetria usa -1 quando a execucao esta parada ou bloqueada por falha.
volatile int8_t modoAplicado=-1;
// Desvio do intervalo entre ativacoes em relacao ao periodo nominal, em us.
volatile int16_t jitterControle=0, jitterSensor=0;
// executar: solicitacao de partida; ativo: execucao permitida neste ciclo.
volatile bool executar=false, ativo=false;
volatile uint8_t falha=0; // 0 normal, 1 sensor, 2 sobretemperatura, 3 saida invalida
// A GUI deve confirmar o ID do pacote antes dos comandos de operacao.
bool autorizado=false;
Transacao transacao;
char linha[48];
uint8_t posicao=0;
bool excedeu=false;
int8_t listar=-1;

// Converte o comando nominal em duty cycle de 0 a 255, limitado ao atuador.
uint8_t pwm(float v,float maximo) {
  if (!isfinite(v) || v<0) v=0;
  if (v>maximo) v=maximo;
  return (uint8_t)(v*255.0f/maximo);
}
// Mede o desvio temporal entre ativacoes, nao a duracao do calculo da tarefa.
// O resultado e limitado a int16_t para transmissao na telemetria.
int16_t jitter(uint32_t agora,uint32_t anterior) {
  int32_t d=(int32_t)(agora-anterior)-SAMPLE_PERIOD_MS*1000L;
  if(d>32767) d=32767;
  if(d< -32768) d=-32768;
  return (int16_t)d;
}
// Inicia a conversao sem manter o barramento ocupado e libera a CPU na espera.
// Retorna NAN se a comunicacao falhar. O byte CRC recebido nao e validado.
float lerTemperaturaSHT20() {

  Wire.beginTransmission(SHT20_ADDR);
  Wire.write(SHT20_TRIGGER_T_NOHOLD);
  if (Wire.endTransmission() != 0) {
    return NAN;
  }

  vTaskDelay(pdMS_TO_TICKS(SHT20_MAX_CONVERSION_MS));

  uint8_t bytesRecebidos = Wire.requestFrom((uint8_t)SHT20_ADDR, (uint8_t)3);

  if (Wire.getWireTimeoutFlag()) {
    Wire.clearWireTimeoutFlag();
    return NAN;
  }

  if (bytesRecebidos < 2) {
    return NAN;
  }

  uint16_t st = (uint16_t)Wire.read() << 8;
  st |= Wire.read();
  if (Wire.available()) {
    Wire.read();
  }

  st &= ~0x0003;

  return -46.85f + 175.72f * ((float)st / 65536.0f);
}


// Aceita apenas um numero finito que ocupe todo o campo recebido.
bool numero(const char* s,float& v) {
  if (!s || !*s) return false;
  char* fim;
  v=strtod(s,&fim);
  return fim!=s && *fim=='\0' && isfinite(v);
}
void resposta(bool ok) { Serial.println(ok ? F("[OK]") : F("[ERRO] Comando/valor/estado invalido")); }
// Protocolo textual da GUI. SET atualiza um parametro; BEGIN/PAR/APLICAR
// prepara um conjunto. A tarefa de Controle efetiva os valores pendentes.
void processar(char* s) {
  if (!strcmp(s,"INFO")) {
    Serial.print(F("[INFO],")); Serial.print(F(PACOTE_ID));
    Serial.print(','); Serial.print(PARAM_COUNT); Serial.println(F(",0.2,MA_SIM_3")); return;
  }
  if (!strncmp(s,"HELLO,",6)) {
    autorizado=!strcmp_P(s+6,PSTR(PACOTE_ID));
    if(!autorizado) { taskENTER_CRITICAL(); executar=false; taskEXIT_CRITICAL(); }
    Serial.print(F("[HELLO],")); Serial.println(autorizado?1:0); return;
  }
  // Parada sempre aceita, mesmo sem identificacao do pacote.
  if (!strcmp(s,"RUN,0")) {
    taskENTER_CRITICAL(); executar=false; cooler=0; manual=0; taskEXIT_CRITICAL();
    Serial.println(F("[OK] Parada solicitada")); return;
  }
  if(!autorizado) { Serial.println(F("[ERRO] Use HELLO,<id do INFO>")); return; }
  bool ok=false;
  if (!strcmp(s,"M,0") || !strcmp(s,"M,1")) {
    uint8_t novo=(uint8_t)(s[2]-'0');
    taskENTER_CRITICAL();
    if(modo!=novo) executar=false;
    modo=novo;
    taskEXIT_CRITICAL();
    ok=true;
  } else if (!strncmp(s,"SET,",4)) {
    char* fim; long indice=strtol(s+4,&fim,10); float v;
    if(fim!=s+4 && *fim==',' && indice>=1 && indice<=PARAM_COUNT && numero(fim+1,v)) {
      taskENTER_CRITICAL();
      if(transacao.estado==Transacao::LIVRE && parametroValido(indice-1,v)) {
        ok=transacao.iniciar() && transacao.definir(indice-1,v) && transacao.confirmar();
      }
      taskEXIT_CRITICAL();
    }
    if(ok) { Serial.println(F("[PENDENTE]")); return; }
  } else if (!strcmp(s,"BEGIN")) {
    taskENTER_CRITICAL(); ok=transacao.iniciar(); taskEXIT_CRITICAL();
  } else if (!strcmp(s,"APLICAR")) {
    taskENTER_CRITICAL(); ok=transacao.confirmar(); taskEXIT_CRITICAL();
    if(ok) { Serial.println(F("[PENDENTE]")); return; }
  } else if (!strcmp(s,"CANCELAR")) {
    taskENTER_CRITICAL(); ok=transacao.cancelar(); taskEXIT_CRITICAL();
  } else if (!strcmp(s,"LISTAR")) {
    listar=0; ok=true;
  } else if (!strcmp(s,"RUN,1")) {
    taskENTER_CRITICAL();
    ok=transacao.estado==Transacao::LIVRE && isfinite(temperatura) && temperatura<55;
    if(ok) executar=true;
    taskEXIT_CRITICAL();
  } else if (!strncmp(s,"PAR,",4)) {
    char* fim;
    long indice=strtol(s+4,&fim,10);
    float v;
    if (fim!=s+4 && *fim==',' && indice>=1 && indice<=PARAM_COUNT && numero(fim+1,v)) {
      taskENTER_CRITICAL(); ok=transacao.definir((uint8_t)(indice-1),v); taskEXIT_CRITICAL();
    }
  } else if ((s[0]=='R' || s[0]=='C' || s[0]=='V') && s[1]==',') {
    float v;
    if(numero(s+2,v)) {
      ok=(s[0]=='R') ? (v>=0 && v<55) : (v>=0 && v<=(s[0]=='V'?12:24));
      if(ok) { taskENTER_CRITICAL(); if(s[0]=='R') referencia=v; else if(s[0]=='C') cooler=v; else manual=v; taskEXIT_CRITICAL(); }
    }
  }
  resposta(ok);
}
void receber() {
  // Limita trabalho por ativacao; uma linha longa e descartada integralmente.
  uint8_t recebidos=0;
  while(Serial.available() && recebidos++<64) {
    char c=Serial.read();
    if(c=='\n' || c=='\r') {
      if(excedeu) Serial.println(F("[ERRO] Linha longa descartada"));
      else if(posicao) { linha[posicao]=0; processar(linha); }
      posicao=0; excedeu=false;
    } else if(!excedeu) {
      if(posicao<sizeof(linha)-1) linha[posicao++]=c;
      else excedeu=true;
    }
  }
}
// Aquisicao periodica. Mantem a ultima leitura valida durante falhas
// transitorias; dez leituras consecutivas invalidas tornam temperatura NAN.
void TaskSensor(void*) {
  TickType_t proxima=xTaskGetTickCount();
  uint32_t anterior=0;
  uint8_t erros=0;
  for(;;) {
    uint32_t agora=micros();
    float t=lerTemperaturaSHT20();
    if(!isfinite(t)) { if(erros<10) ++erros; }
    else erros=0;
    taskENTER_CRITICAL();
    if(anterior) jitterSensor=jitter(agora,anterior);
    if(!erros) temperatura=t;
    else if(erros>=10) temperatura=NAN;
    taskEXIT_CRITICAL();
    anterior=agora;
    // Mantem a referencia periodica pelo tick do RTOS; o intervalo real pode
    // diferir do nominal e e acompanhado pelo desvio enviado na telemetria.
    vTaskDelayUntil(&proxima,pdMS_TO_TICKS(SAMPLE_PERIOD_MS));
  }
}
// Executa o controlador e atualiza os atuadores a cada periodo nominal.
// Aplica parametros antes do passo de controle e verifica as protecoes.
void TaskControl(void*) {
  TickType_t proxima=xTaskGetTickCount();
  uint32_t anterior=0;
  bool estavaAtivo=false, quente=false;
  uint8_t modoAnterior=255;
  simulinkInicializar();
  for(;;) {
    uint32_t agora=micros();
    float t,r,c,mv; uint8_t m;
    bool ligar,commit;
    taskENTER_CRITICAL();
    if(anterior) jitterControle=jitter(agora,anterior);
    t=temperatura; r=referencia; c=cooler; ligar=executar; mv=manual; m=modo;
    commit=transacao.estado==Transacao::PENDENTE;
    if(commit) transacao.estado=Transacao::APLICANDO;
    taskEXIT_CRITICAL();
    anterior=agora;
    // O conjunto e aplicado pela propria tarefa de Controle, entre dois passos.
    if(commit) {
      transacao.aplicar(); // Serial nao altera valores enquanto APLICANDO.
      taskENTER_CRITICAL(); transacao.estado=Transacao::CONCLUIDA; taskEXIT_CRITICAL();
    }
    // Histerese da protecao termica: bloqueia em 55 C e libera em 52 C.
    // A falha cancela a partida; voltar a faixa permitida nao reinicia sozinho.
    if(isfinite(t) && t>=55) quente=true;
    else if(isfinite(t) && t<=52) quente=false;
    uint8_t erro=!isfinite(t) ? 1 : (quente ? 2 : 0);
    bool rodar=ligar && !erro;
    float u=0;
    // Reinicia os estados do modelo ao iniciar ou trocar o modo de operacao.
    if(rodar && (!estavaAtivo || m!=modoAnterior)) simulinkInicializar();
    if(rodar) {
      u=(m==0) ? mv : simulinkExecutar(r,t,SAMPLE_PERIOD_MS/1000.0f);
      if(!isfinite(u)) { u=0; erro=3; rodar=false; }
    }
    if(!rodar && estavaAtivo) simulinkInicializar();
    estavaAtivo=rodar; modoAnterior=m;
    taskENTER_CRITICAL();
    // Uma parada recebida durante o calculo tem precedencia sobre a saida.
    if(!executar || modo!=m) { u=0; rodar=false; c=0; }
    if(erro) executar=false; // Falha exige novo RUN,1; nao religa sozinha.
    aplicado=u; ativo=rodar; modoAplicado=rodar?(int8_t)m:-1; falha=erro;
    analogWrite(PIN_LAMPADA_PWM,pwm(u,12));
    analogWrite(PIN_COOLER_PWM,pwm(c,24));
    taskEXIT_CRITICAL();
    vTaskDelayUntil(&proxima,pdMS_TO_TICKS(SAMPLE_PERIOD_MS));
  }
}
// Recebe comandos e publica telemetria no periodo nominal. A confirmacao
// APLICADO so e enviada depois que a tarefa de Controle efetiva a transacao.
void TaskSerial(void*) {
  TickType_t proxima=xTaskGetTickCount();
  for(;;) {
    receber();
    bool concluiu;
    taskENTER_CRITICAL();
    concluiu=transacao.estado==Transacao::CONCLUIDA;
    if(concluiu) transacao.estado=Transacao::LIVRE;
    taskEXIT_CRITICAL();
    if(concluiu) Serial.println(F("[APLICADO]"));
    if(listar>=0) {
      if(listar<PARAM_COUNT) {
        float v; taskENTER_CRITICAL(); v=parametroLer(listar); taskEXIT_CRITICAL();
        Serial.print(F("[PAR],")); Serial.print(listar+1); Serial.print(','); Serial.println(v,6); ++listar;
      } else { Serial.println(F("[LISTA_FIM]")); listar=-1; }
    }
    float t,r,u; int16_t jc,js; int8_t ma; uint8_t f;
    taskENTER_CRITICAL();
    t=temperatura; r=referencia; u=aplicado; jc=jitterControle; js=jitterSensor; ma=modoAplicado; f=falha;
    taskEXIT_CRITICAL();
    // Formato: D,modo,referencia,temperatura,U,ms,jitterC,jitterS,falha.
    // ms: instante de transmissao desde o boot; jitterC/jitterS: desvios em us.
    Serial.print(F("D,")); Serial.print((int)ma); Serial.print(',');
    Serial.print(r,2); Serial.print(','); Serial.print(t,2); Serial.print(',');
    Serial.print(u,2); Serial.print(','); Serial.print(millis()); Serial.print(',');
    Serial.print(jc); Serial.print(','); Serial.print(js); Serial.print(','); Serial.println(f);
    vTaskDelayUntil(&proxima,pdMS_TO_TICKS(SAMPLE_PERIOD_MS));
  }
}
// Uma falha na criacao das tarefas mantem os atuadores desenergizados.
void criar(TaskFunction_t fn,const char* nome,uint16_t pilha,UBaseType_t prioridade) {
  if(xTaskCreate(fn,nome,pilha,NULL,prioridade,NULL)!=pdPASS) {
    analogWrite(PIN_LAMPADA_PWM,0); analogWrite(PIN_COOLER_PWM,0);
    Serial.println(F("[FATAL] Falha ao criar tarefa")); Serial.flush(); for(;;) {}
  }
}
// Inicializa a bancada parada e cria as tres tarefas antes do escalonador.
void setup() {
  MCUSR=0; wdt_disable();
  pinMode(PIN_LAMPADA_PWM,OUTPUT); pinMode(PIN_LAMPADA_DIR,OUTPUT);
  pinMode(PIN_COOLER_PWM,OUTPUT); pinMode(PIN_COOLER_DIR,OUTPUT);
  digitalWrite(PIN_LAMPADA_DIR,LOW); digitalWrite(PIN_COOLER_DIR,LOW);
  analogWrite(PIN_LAMPADA_PWM,0); analogWrite(PIN_COOLER_PWM,0);
  Serial.begin(115200); Wire.begin(); Wire.setWireTimeout(3000,true);
  Serial.println(F("TCC - Malha Aberta + Simulink; inicializa parado"));
  // Sensor e Controle: prioridade 3; Serial: prioridade 1.
  // Sensor e Controle possuem ciclos independentes e compartilham a ultima
  // temperatura publicada; nao ha sincronizacao de uma nova leitura por passo.
  criar(TaskSensor,"Sensor",STACK_SENSOR,3);
  criar(TaskControl,"Control",STACK_CONTROL,3);
  criar(TaskSerial,"Serial",STACK_SERIAL,1);
  Serial.flush(); vTaskStartScheduler();
  for(;;) {}
}
void loop() {}
