# Controle em tempo real com FreeRTOS e Simulink

Metodologia para integrar controladores desenvolvidos no **MATLAB/Simulink** a uma plataforma embarcada com **FreeRTOS**, aplicada a uma planta térmica didática HVAC.

O projeto reúne a geração automática de código C, sua integração ao firmware, a execução periódica no microcontrolador e uma interface de supervisão para configurar ensaios, ajustar parâmetros e comparar as respostas simulada e experimental.

**Trabalho de Conclusão de Curso — Engenharia de Controle e Automação, UFRGS**  
**Autor:** Thiago Miorando Tavolara  
**Orientador:** Prof. Marcelo Götz

## Proposta

A infraestrutura permite substituir o controlador gerado pelo Simulink preservando as tarefas de aquisição, controle e comunicação, desde que o novo controlador respeite a interface de integração e os recursos disponíveis no microcontrolador.

O fluxo de utilização compreende:

1. Caracterizar a planta e definir os requisitos de operação.
2. Obter um modelo da planta para apoiar as simulações.
3. Projetar e avaliar o controlador no Simulink.
4. Gerar e importar o código do controlador.
5. Compilar, gravar e executar o firmware com FreeRTOS.
6. Configurar os ensaios e ajustar os parâmetros pela interface de supervisão.
7. Registrar os dados e comparar simulação e planta.

O modelo da planta permanece no ambiente de simulação. O código embarcado é gerado para o **subsistema do controlador**.

## Bancada e implementação

| Elemento | Configuração utilizada |
|---|---|
| Microcontrolador | Arduino Nano com ATmega328P a 16 MHz |
| Memória | 2 KiB de SRAM e 32 KiB de Flash |
| Sensor | SHT20, conectado por I²C |
| Aquecimento | Lâmpada de 12 V/50 W, acionada por PWM |
| Ventilação | Cooler de 24 V, acionado por PWM |
| Comunicação | UART a 115200 baud |
| Período nominal | 200 ms, equivalente a 50 *ticks* |
| Base de tempo do FreeRTOS | Timer2 em modo CTC, divisor 256 e `OCR2A = 249`: *tick* nominal de 4 ms |

O firmware organiza a aplicação em três tarefas:

| Tarefa | Responsabilidade | Prioridade | Período nominal |
|---|---|---:|---:|
| `TaskSensor` | Aquisição e validação da temperatura | 2 | 200 ms |
| `TaskControl` | Aplicação de parâmetros, execução do controlador e atuação | 2 | 200 ms |
| `TaskSerial` | Recepção de comandos e transmissão de respostas e telemetria | 1 | 200 ms |

As tarefas utilizam `vTaskDelayUntil()`. Aquisição e controle possuem ciclos independentes: o controlador utiliza a última temperatura disponibilizada pelo sensor.

O modo **0** corresponde à malha aberta; o modo **1**, ao controlador importado do Simulink. PID e liga-desliga utilizam o mesmo modo 1, conforme o código gravado no Arduino.

Os comandos dos atuadores são expressos em uma escala nominal de tensão utilizada no acionamento PWM. Não representam uma medição direta da tensão nos terminais ou da potência elétrica dissipada.

## Requisitos

| Ferramenta ou recurso | Utilização |
|---|---|
| MATLAB/Simulink **R2014a** | Ambiente utilizado no trabalho: modelos, scripts e interface de supervisão |
| Simulink Coder e Embedded Coder | Geração de código C com alvo `ert` |
| Optimization Toolbox | Identificação da planta com `lsqnonlin`, quando essa etapa for utilizada |
| Visual Studio Code com [PlatformIO](https://platformio.org/) | Compilação e gravação do firmware |
| Bancada e conexão USB | Execução dos ensaios físicos e comunicação com o Arduino |

O arquivo [`platformio.ini`](platformio.ini) seleciona a placa `nanoatmega328new`, a plataforma `atmelavr@5.3.0` e o framework Arduino. A cópia da biblioteca FreeRTOS adaptada para o Timer2 já está incluída em [`lib/FreeRTOS/`](lib/FreeRTOS/).

## Primeiros passos

### 1. Preparar o MATLAB

Abra o MATLAB com a pasta atual na raiz do repositório e execute:

```matlab
raiz = pwd;
addpath(fullfile(raiz, 'GUI'));
addpath(fullfile(raiz, ...
    'exemplos_preparar_parametros_controladores_simulink'));
configurar_pastas_simulink;
```

A rotina configura os destinos de geração de código e de arquivos temporários. As duas chamadas a `addpath` também tornam acessíveis a interface de supervisão e os scripts de exemplo.

### 2. Preparar o controlador

Escolha um modelo em [`base_controladores_simulink/`](base_controladores_simulink/):

| Modelo | Finalidade |
|---|---|
| `simulink_base_.slx` | Base para construir uma estratégia de controle |
| `simulink_base_PID.slx` | Exemplo com controlador PID |
| `simulink_base_Bang_Bang.slx` | Exemplo com controle liga-desliga com histerese |

Implemente a estratégia dentro do subsistema `Controlador`, preservando as entradas `Referencia` e `Temperatura` e a saída `U`. Configure o controlador discreto com período de **0,2 s** e considere os limites de atuação de **0 a 12 V** para o aquecimento.

Cadastre os parâmetros ajustáveis com `parametro_ajustavel(nome, valor, minimo, maximo)`, utilizando os mesmos nomes nos campos dos blocos do Simulink. Por exemplo, para os ensaios PID com `P = 4`:

```matlab
parametro_ajustavel('P',   4, 0, 100);
parametro_ajustavel('I',   1, 0,  20);
parametro_ajustavel('D', 0.2, 0,  10);
parametro_ajustavel('N',   5, 0, 100);
```

Para o exemplo liga-desliga:

```matlab
parametro_ajustavel('hist_max',  0.5,  0.01,  5);
parametro_ajustavel('hist_min', -0.5, -5,    -0.01);
parametro_ajustavel('u_max',      12,  0,    12);
parametro_ajustavel('u_min',       0,  0,    12);
```

Execute apenas o conjunto correspondente ao controlador escolhido. Os scripts `preparar_pid.m` e `preparar_bangbang.m`, na pasta de exemplos, também podem servir de ponto de partida; seus valores e limites devem ser conferidos antes do uso. No terceiro ensaio PID do TCC, foi utilizado `P = 3`.

Avalie a resposta em simulação antes de gerar o código. As sintonias apresentadas correspondem à bancada estudada e precisam ser reavaliadas para outra planta.

### 3. Gerar, importar e gravar

1. Gere o código do subsistema `Controlador` pela opção **Build This Subsystem**, com configuração de hardware compatível com AVR.
2. Execute no MATLAB:

   ```matlab
   importar_controlador;
   ```

3. Selecione a pasta de código gerado com sufixo `_ert_rtw`.
4. Abra a raiz do projeto no PlatformIO e execute **Build** e **Upload**.

A importação atualiza as fontes em `src/gerado/`, os arquivos de integração em `src/` e o perfil do controlador. Gerar código no Simulink, isoladamente, não atualiza o controlador gravado no Arduino.

### 4. Executar um ensaio

Abra a interface de supervisão:

```matlab
HVAC_TCC_GUI;
```

1. Selecione a porta serial e clique em **Conectar**.
2. Aguarde a conferência da identificação do controlador.
3. Selecione o modo de operação e configure a referência e o comando do cooler.
4. Se necessário, ajuste os valores em **Parâmetros Simulink** e aguarde a confirmação de aplicação.
5. Clique em **Aplicar / iniciar** e acompanhe temperatura e comando.
6. Ao concluir, clique em **PARAR PLANTA** e verifique a interrupção da atuação.
7. Utilize **Salvar ensaio** para guardar o CSV e o histórico textual antes de limpar os registros.

O [guia visual de utilização](documentacao/Guia_Visual_Simulink_Arduino.pdf) apresenta o procedimento com capturas de tela.

## Ajuste de parâmetros e troca de controlador

A integração admite até **16 valores ajustáveis**, contando separadamente cada elemento de um parâmetro vetorial. Os valores devem ser cadastrados antes da geração de código e respeitar os limites definidos.

Parâmetros já cadastrados podem ser modificados pela interface durante a execução, sem gerar novamente o código ou regravar o Arduino. As alterações permanecem na RAM; após uma reinicialização, são restaurados os valores incorporados ao firmware.

Alterar a estrutura do controlador ou a lista de parâmetros exige nova geração, importação, compilação e gravação. A versão atual do importador aceita apenas **0,2 s**: adotar outro período requer revisar essa restrição e manter coerentes o modelo, a integração, o firmware e o período informado à interface.

## Comparação entre simulação e planta

1. Execute e salve o ensaio físico em CSV, acompanhado do histórico da sessão.
2. Reproduza no Simulink as condições correspondentes: referência, parâmetros, temperatura inicial, limites de atuação e condição do cooler.
3. Execute a simulação. Nos modelos preparados, as rotinas de registro exportam os sinais para `dados/simulacoes/`. Se criar outro modelo ou remover os registros, utilize `preparar_modelo_comparacao` para configurar essa etapa.
4. Na interface, abra **Simulação x planta**, selecione o CSV e depois o MAT.
5. Confira o trecho e o alinhamento temporal por um evento correspondente. A comparação utiliza o intervalo comum aos registros.
6. Utilize **Salvar comparação (.mat)** e **Exportar gráficos (.png)** para guardar os resultados. A pasta sugerida é `dados/comparacoes/`.

A interface não atualiza automaticamente os parâmetros do modelo Simulink: reaplique no modelo os valores utilizados na planta antes de simular.

RMSE, MAE e erro máximo quantificam as diferenças entre simulação e planta. Esses indicadores não equivalem ao erro de acompanhamento da referência e devem ser interpretados juntamente com os gráficos e a duração dos registros.

## Ensaios apresentados no TCC

Os quatro ensaios em malha fechada estão em [`dados/ensaios/Ensaios utilizados no tcc/`](<dados/ensaios/Ensaios utilizados no tcc/>). Cada pasta reúne o CSV e o histórico da planta, a simulação, os arquivos da comparação e um `DADOS.txt` com as condições utilizadas.

| Pasta | Controlador | Referência | Parâmetros | Temperatura inicial da simulação |
|---|---|---|---|---|
| `1_PID_referência_de_28_C` | PID | 28 °C | P = 4, I = 1, D = 0,2, N = 5 | 24,46 °C |
| `2_PID_referência_de_30_C` | PID | 30 °C | P = 4, I = 1, D = 0,2, N = 5 | 23,92 °C |
| `3_PID_com_outra_sintonia_30_C` | PID | 30 °C | P = 3, I = 1, D = 0,2, N = 5 | 23,13 °C |
| `4_Bang_bang_referência_de_30_C` | Liga-desliga | 30 °C | Limiares de erro ±0,5 °C; comandos de 0 e 12 V | 24,15 °C |

Todos utilizaram período nominal de **0,2 s**, com o **cooler desligado**. A temperatura inicial indicada é a condição adotada na simulação e pode diferir ligeiramente da primeira medição experimental.

| Ensaio | Amostras comparadas | Duração (s) | RMSE (°C) | MAE (°C) | Erro absoluto máximo (°C) |
|---|---:|---:|---:|---:|---:|
| PID, 28 °C, P = 4 | 294 | 58,60 | 0,039 | 0,012 | 0,306 |
| PID, 30 °C, P = 4 | 229 | 45,60 | 0,065 | 0,027 | 0,385 |
| PID, 30 °C, P = 3 | 172 | 34,20 | 0,077 | 0,040 | 0,334 |
| Liga-desliga, 30 °C | 282 | 56,20 | 0,537 | 0,312 | 2,734 |

As métricas referem-se à diferença entre as temperaturas medida e simulada. O registro `timer2_planta_parada.csv`, disponível na mesma pasta principal, é complementar e não integra esses quatro ensaios.

O modelo térmico utilizado nas simulações foi identificado a partir de dois ensaios em malha aberta e reúne três parcelas de primeira ordem em paralelo com atraso equivalente. Os parâmetros, o resultado do ajuste e as figuras estão em [`dados/identificacoes/resultado_identificao_planta/`](dados/identificacoes/resultado_identificao_planta/).

O pacote de referência distribuído com o projeto contém o controlador **liga-desliga**, identificado por `328856e577efcd11`. Para executar o PID, gere o código do subsistema `Controlador` do modelo `simulink_base_PID.slx`, importe, compile e grave o firmware. Uma nova importação pode alterar o identificador do pacote.

## Organização dos arquivos

| Caminho | Conteúdo |
|---|---|
| `src/` | Firmware, tarefas FreeRTOS, protocolo, proteções e ponte de execução |
| `src/gerado/` | Fontes do controlador importado do Simulink |
| `lib/FreeRTOS/` | Biblioteca FreeRTOS para AVR com base de tempo adaptada para o Timer2 |
| `GUI/` | Interface de supervisão `HVAC_TCC_GUI.m` |
| `base_controladores_simulink/` | Modelos-base com controlador, planta simulada e registros |
| `exemplos_preparar_parametros_controladores_simulink/` | Scripts de cadastro dos parâmetros dos exemplos |
| `codigo_gerado_simulink/` | Arquivos produzidos pela geração de código, antes da importação |
| `dados/ensaios/` | Registros experimentais e conjuntos de ensaios |
| `dados/simulacoes/` | Destino das simulações exportadas |
| `dados/comparacoes/` | Destino sugerido para comparações e gráficos |
| `dados/identificacoes/` | Resultados da identificação da planta |
| `documentacao/` | Guia visual em PDF e DOCX |
| Arquivos `*.m` na raiz | Rotinas de preparação, importação, identificação e comparação |
| `perfil_controlador.txt` | Identificação do pacote e descrição dos parâmetros para a interface |
| `registro_parametros.mat` | Cadastro dos parâmetros ajustáveis utilizado na importação |
| `platformio.ini` | Configuração da plataforma, placa e framework |

Os diretórios de saída podem ser criados pelas rotinas durante o uso. Mantenha os registros experimentais associados às respectivas configurações e simulações.

## Autoria e créditos

- **Implementação do trabalho:** firmware da aplicação, interface de supervisão, scripts MATLAB, modelos e material de apoio — Thiago Miorando Tavolara, sob orientação do Prof. Marcelo Götz.
- **Código gerado:** as fontes do controlador são produzidas pelo Simulink Coder/Embedded Coder e integradas ao firmware pelas rotinas do projeto.
- **FreeRTOS para AVR:** biblioteca disponibilizada por Phillip Stevens no projeto [Arduino FreeRTOS Library](https://github.com/feilipu/Arduino_FreeRTOS_Library), versão 11.1.0-3, sob licença MIT. A cópia local inclui a adaptação da base de tempo para o Timer2. Os avisos de autoria e licença da biblioteca estão preservados em seus arquivos.
- **Plataforma Atmel AVR e framework Arduino:** obtidos pelo PlatformIO conforme `platformio.ini`.
- MATLAB e Simulink são marcas registradas da The MathWorks, Inc.
