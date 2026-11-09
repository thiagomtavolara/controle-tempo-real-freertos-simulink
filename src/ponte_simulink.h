/*
 * Interface de acesso ao controlador Simulink pelo firmware.
 * Autor: Thiago Miorando Tavolara
 * TCC em Engenharia de Controle e Automacao - UFRGS
 * Orientacao: Prof. Marcelo Gotz
 */
#ifndef PONTE_SIMULINK_H
#define PONTE_SIMULINK_H
// Chamar na inicializacao e nas transicoes de execucao previstas no firmware.
void simulinkInicializar();
// Retorna o comando da lampada entre 0 e 12 V, ou NAN em caso de falha.
// periodo e o intervalo nominal esperado, em segundos; nao e o tempo medido.
float simulinkExecutar(float referencia, float temperatura, float periodo);
#endif
