% PREPARAR_PID Cadastra os parametros ajustaveis do exemplo PID.
%
% Execute com parametro_ajustavel.m acessivel no path do MATLAB, antes de
% simular ou gerar o subsistema. Use P, I, D e N nos campos do bloco PID.
% N e o coeficiente do filtro derivativo. Preserve a forma ideal ou paralela
% e a discretizacao correspondentes a sintonia adotada no modelo.
% Os valores e limites abaixo sao ilustrativos, nao uma sintonia universal.
%
% Autor: Thiago Miorando Tavolara
% TCC em Engenharia de Controle e Automacao - UFRGS
% Orientacao: Prof. Marcelo Gotz

% Valores ilustrativos. Usar os ganhos da sintonia validada pelo aluno.
parametro_ajustavel('P',3,0,10);
parametro_ajustavel('I',1,0,10);
parametro_ajustavel('D',0.2,0,10);
parametro_ajustavel('N',5,0.1,100);

% No bloco PID discreto, usar P, I, D e N nos campos correspondentes.
% Manter a forma do PID (ideal ou paralela) adotada na sintonia.
% Configurar amostragem de 0.2 s, saturacao e anti-windup no modelo.
% Os limites acima sao ilustrativos e podem ser ajustados ao controlador.
% Se ajustar pela GUI, reaplique aqui os valores do trecho antes de simular.
% Este script prepara o Workspace e o cadastro; nao envia comandos ao Arduino.
