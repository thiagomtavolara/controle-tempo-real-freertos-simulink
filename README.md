# Controle em tempo real com FreeRTOS e Simulink

Infraestrutura para projetar um controlador no **Simulink**, gerar o código C,
executá-lo em um **Arduino Nano com FreeRTOS** sobre uma planta térmica didática
(HVAC) e comparar o comportamento real com a simulação.

Trabalho de Conclusão de Curso em Engenharia de Controle e Automação — **UFRGS**  
Autor: **Thiago Miorando Tavolara** · Orientação: **Prof. Marcelo Götz**

---

## O que dá para fazer

- **Projetar** a lei de controle no Simulink, dentro de um subsistema com entradas
  `Referencia` e `Temperatura` e saída `U` (0 a 12 V).
- **Gerar e importar** o controlador para o firmware sem escrever código C à mão.
- **Executar na planta** com período nominal de 0,2 s, sob escalonamento do FreeRTOS
  (*tick* de 4 ms gerado pelo Timer2).
- **Ajustar parâmetros pela GUI** (até 16 valores) sem regravar o Arduino.
- **Registrar ensaios** em CSV e **comparar** com a simulação (RMSE, MAE e erro máximo).
- **Identificar** um modelo térmico da planta a partir de ensaios em malha aberta.

## Requisitos

| Item | Uso |
|---|---|
| MATLAB/Simulink **R2014a** | Modelagem, GUI e scripts |
| Simulink Coder + Embedded Coder | Geração de código (alvo `ert`) |
| Optimization Toolbox | Apenas para `identificar_planta_atraso` (`lsqnonlin`) |
| [PlatformIO](https://platformio.org/) (VS Code) | Compilação e gravação; o FreeRTOS já vem em `lib/FreeRTOS/` |
| Bancada | Arduino Nano (ATmega328P), sensor SHT20, lâmpada e cooler acionados por PWM |

## Por onde começar

1. Abra o MATLAB na raiz do repositório e prepare o caminho:

   ```matlab
   % Execute inicialmente na raiz do repositório:
   raiz = pwd;
   addpath(fullfile(raiz, 'GUI'));
   addpath(fullfile(raiz, ...
       'exemplos_preparar_parametros_controladores_simulink'));
   configurar_pastas_simulink;
   ```

2. Parta de um modelo em [`base_controladores_simulink/`](base_controladores_simulink):
   `simulink_base_PID.slx`, `simulink_base_Bang_Bang.slx` ou a base vazia `simulink_base_.slx`.
3. Cadastre os parâmetros ajustáveis com os exemplos de
   [`exemplos_preparar_parametros_controladores_simulink/`](exemplos_preparar_parametros_controladores_simulink)
   (`preparar_pid.m`, `preparar_bangbang.m`).
4. Gere o código do subsistema `Controlador` (*Build This Subsystem*) e importe:

   ```matlab
   preparar_pid                      % ou preparar_bangbang / seus parâmetros
   % Simulink: Build This Subsystem no subsistema Controlador
   importar_controlador              % atualiza src/gerado e perfil_controlador.txt
   ```

5. No PlatformIO, faça **Build** e **Upload**.
6. Abra a supervisão com `HVAC_TCC_GUI` (pasta `GUI/`), conecte a porta serial e
   selecione o modo 1 (controlador Simulink).

O [guia visual](documentacao/Guia_Visual_Simulink_Arduino.pdf) mostra essas etapas
com capturas de tela.

## Comparação entre simulação e planta

1. Execute o ensaio na planta e salve o CSV e o log pela GUI (**Salvar ensaio**).
2. Reproduza no Simulink as mesmas condições: temperatura inicial, referência e
   parâmetros (`parametro_ajustavel`). A simulação é salva em `dados/simulacoes`.
3. Na interface, use **Simulação x planta**, selecione o CSV e depois o MAT. Para
   salvar os resultados, utilize **Salvar comparação (.mat)** e **Exportar gráficos
   (.png)**. A pasta sugerida é `dados/comparacoes`.

A GUI não altera os parâmetros do Simulink: reaplique no modelo os valores usados
na planta antes de simular.

## Organização dos arquivos

| Caminho | Conteúdo |
|---|---|
| `src/` | Firmware: tarefas FreeRTOS, comunicação serial, proteções e ponte com o controlador |
| `src/gerado/` | Controlador gerado pelo Simulink e integrado por `importar_controlador` |
| `lib/FreeRTOS/` | FreeRTOS 11.1.0-3 adaptado para gerar o *tick* do escalonador pelo Timer2 |
| `GUI/` | `HVAC_TCC_GUI.m`, interface de supervisão e comparação |
| `base_controladores_simulink/` | Modelos-base (vazio, PID e liga-desliga) com a planta simulada e os registros |
| `exemplos_preparar_parametros_controladores_simulink/` | Cadastro dos parâmetros ajustáveis dos exemplos |
| `codigo_gerado_simulink/` | Saída da última geração de código, anterior à importação |
| `dados/` | Ensaios, identificação da planta, simulações e comparações |
| `documentacao/` | Guia visual (PDF e DOCX) |
| `*.m` (raiz) | Importação, cadastro de parâmetros, identificação, registro e comparação |
| `perfil_controlador.txt`, `registro_parametros.mat` | Identificação do pacote instalado e cadastro dos parâmetros |
| `platformio.ini` | Placa e plataforma do firmware |

## Ensaios do TCC

Os dados apresentados no trabalho estão em
[`dados/ensaios/Ensaios utilizados no tcc/`](<dados/ensaios/Ensaios utilizados no tcc>).
Cada pasta de ensaio contém o CSV e o log da planta, o MAT da simulação, o MAT e a
figura da comparação, e um `DADOS.txt` com as condições do ensaio.

| Pasta | Controlador | Referência | Parâmetros | T inicial da simulação |
|---|---|---|---|---|
| `1_PID_referência_de_28_C` | PID | 28 °C | P = 4, I = 1, D = 0,2, N = 5 | 24,46 °C |
| `2_PID_referência_de_30_C` | PID | 30 °C | P = 4, I = 1, D = 0,2, N = 5 | 23,92 °C |
| `3_PID_com_outra_sintonia_30_C` | PID | 30 °C | P = 3, I = 1, D = 0,2, N = 5 | 23,13 °C |
| `4_Bang_bang_referência_de_30_C` | Liga-desliga | 30 °C | histerese ±0,5 °C, saída 0 / 12 V | 24,15 °C |

Todos com período de 0,2 s e cooler desligado. A temperatura inicial é a condição
adotada na simulação; em dois ensaios, difere ligeiramente da primeira temperatura
medida. Na mesma pasta,
`timer2_planta_parada.csv` registra a planta parada, sem atuação.

O modelo da planta usado nas simulações está em
[`dados/identificacoes/resultado_identificao_planta/`](dados/identificacoes/resultado_identificao_planta):
parâmetros (`parametros.txt`), resultado do ajuste (`resultado_atraso.mat`) e figuras.

O controlador presente em `src/gerado/` é o **liga-desliga** (pacote `328856e577efcd11`).
Para executar o PID, gere e importe o modelo `simulink_base_PID.slx`.

## Autoria e créditos

- **Implementação deste trabalho:** firmware em `src/` (exceto `src/gerado/`), GUI,
  scripts MATLAB, modelos-base e guia — Thiago Miorando Tavolara.
- **Código gerado:** `src/gerado/` e `codigo_gerado_simulink/` são produzidos pelo
  Simulink Coder/Embedded Coder a partir dos modelos deste repositório.
- **FreeRTOS:** `lib/FreeRTOS/` é uma cópia do
  [FreeRTOS para AVR](https://github.com/feilipu/Arduino_FreeRTOS_Library)
  (versão 11.1.0-3, licença MIT). Foram alterados apenas `src/FreeRTOSVariant.h` e
  `src/port.c`, para gerar o *tick* pelo Timer2 em vez do *watchdog*.
- **Plataforma Atmel AVR** (`atmelavr@5.3.0`) e **framework Arduino**: obtidos pelo
  PlatformIO durante a preparação do ambiente.
- MATLAB e Simulink são marcas registradas da The MathWorks, Inc.
