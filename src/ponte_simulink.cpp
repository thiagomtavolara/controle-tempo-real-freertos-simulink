/*
 * Integracao entre a tarefa de Controle e o controlador gerado pelo Simulink.
 * Autor: Thiago Miorando Tavolara
 * TCC em Engenharia de Controle e Automacao - UFRGS
 * Orientacao: Prof. Marcelo Gotz
 */
// O importador define os nomes do modelo em modelo_selecionado.h.
// A lei de controle permanece nos arquivos gerados, em src/gerado.
#include "ponte_simulink.h"
#include "modelo_selecionado.h"
#include <math.h>
#include <limits.h>
// Tipos devem corresponder ao alvo. Nunca corrija rtwtypes.h manualmente:
// configure Hardware Implementation no Simulink e gere novamente.
static_assert(sizeof(int32_T)*CHAR_BIT == 32,
              "Simulink: regenere para o alvo AVR; int32_T deve ter 32 bits");
static_assert(sizeof(int16_T)*CHAR_BIT == 16, "int16_T incompativel");
static_assert(sizeof(int8_T)*CHAR_BIT == 8, "int8_T incompativel");
// Inicializa ou reinicia os estados conforme a rotina gerada pelo Simulink.
void simulinkInicializar() { MODELO_INICIAR(); }
// Executa um passo com referencia/temperatura em C e periodo nominal em s.
// NAN sinaliza falha para a tarefa de Controle interromper a execucao.
float simulinkExecutar(float referencia, float temperatura, float periodo) {
  // Confere as entradas e a compatibilidade com o periodo do modelo.
  if (!isfinite(referencia) || !isfinite(temperatura) ||
      !isfinite(periodo) || fabs(periodo-MODELO_PERIODO_S)>0.000001f) {
    MODELO_INICIAR();
    return NAN;
  }
  // Atualiza as entradas antes de chamar o passo do controlador.
  MODELO_ENTRADAS.Referencia = referencia;
  MODELO_ENTRADAS.Temperatura = temperatura;
  MODELO_PASSO();
  // A saida representa o comando nominal da lampada, em volts.
  double u = MODELO_SAIDAS.U;
  if (!isfinite(u)) { MODELO_INICIAR(); return NAN; }
  // Limite adicional da bancada; nao substitui o anti-windup no modelo.
  if (u > 12.0) u = 12.0;
  if (u < 0.0) u = 0.0;
  return (float)u;
}
