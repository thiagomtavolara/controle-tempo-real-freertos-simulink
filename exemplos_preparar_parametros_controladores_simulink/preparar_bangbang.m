% PREPARAR_BANGBANG Cadastra os parametros ajustaveis do exemplo liga-desliga.
%
% Execute com parametro_ajustavel.m acessivel no path do MATLAB, antes de
% simular ou gerar o subsistema. O Relay recebe Referencia - Temperatura.
% hist_max/hist_min definem os limiares do erro em C; u_max/u_min definem
% os comandos nominais da lampada em V. Os valores abaixo sao ilustrativos.
% As faixas dos limiares preservam hist_max > hist_min. As faixas das saidas
% sao independentes: ao ajustar, mantenha tambem u_max > u_min.
%
% Autor: Thiago Miorando Tavolara
% TCC em Engenharia de Controle e Automacao - UFRGS
% Orientacao: Prof. Marcelo Gotz

% Valores ilustrativos para o controlador liga-desliga com histerese.
parametro_ajustavel('hist_max',0.5,0.01,5);
parametro_ajustavel('hist_min',-0.5,-5,-0.01);
parametro_ajustavel('u_max',12,0,12);
parametro_ajustavel('u_min',0,0,12);

% No bloco Relay, usar:
% Switch on point  = hist_max
% Switch off point = hist_min
% Output when on   = u_max
% Output when off  = u_min

% Entrada do Relay: erro = Referencia - Temperatura.
% Manter hist_max > hist_min e u_max > u_min.
% Configurar amostragem de 0.2 s no controlador.
% Conferir a exportacao dos quatro parametros no codigo C gerado.
% Se ajustar pela GUI, reaplique aqui os valores do trecho antes de simular.
% Este script prepara o Workspace e o cadastro; nao envia comandos ao Arduino.
