/*
 * Preparacao e aplicacao dos parametros ajustaveis do controlador.
 * Autor: Thiago Miorando Tavolara
 * TCC em Engenharia de Controle e Automacao - UFRGS
 * Orientacao: Prof. Marcelo Gotz
 */
#pragma once
#include <stdint.h>
#include <math.h>
#include "parametros_modelo.h"
// A tarefa Serial prepara os valores e solicita sua aplicacao. A tarefa de
// Controle efetiva o conjunto antes do proximo passo do controlador.
// A classe nao cria bloqueios: o chamador protege o estado compartilhado
// com secoes criticas, conforme o uso em main.cpp.
class Transacao {
 public:
  // LIVRE: aceita nova edicao; EDITANDO: recebe os valores propostos.
  // PENDENTE: aguarda Controle; APLICANDO: Controle escreve os parametros.
  // CONCLUIDA: aguarda Serial confirmar e liberar uma nova transacao.
  enum Estado { LIVRE, EDITANDO, PENDENTE, APLICANDO, CONCLUIDA };
  volatile Estado estado;
  // Reserva ao menos uma posicao para modelos sem parametros ajustaveis.
  float valores[PARAM_COUNT ? PARAM_COUNT : 1];
  bool alterado;
  Transacao(): estado(LIVRE), alterado(false) {}
  // Copia os valores atuais. Se ja estiver EDITANDO, descarta a edicao anterior.
  bool iniciar() {
    if (estado == PENDENTE || estado == APLICANDO || estado == CONCLUIDA) return false;
    for (uint8_t i=0; i<PARAM_COUNT; ++i) valores[i]=parametroLer(i);
    alterado=false; estado=EDITANDO; return true;
  }
  // Altera somente a copia de trabalho; os valores do controlador nao mudam.
  // Indices internos comecam em zero; o protocolo serial usa indices desde um.
  bool definir(uint8_t i, float v) {
    if (estado!=EDITANDO || i>=PARAM_COUNT || !isfinite(v) || !parametroValido(i,v)) return false;
    valores[i]=v; alterado=true; return true;
  }
  // Solicita aplicacao de uma edicao valida; ainda nao escreve no controlador.
  bool confirmar() {
    if (estado!=EDITANDO || !alterado) return false;
    estado=PENDENTE; return true;
  }
  // Depois da confirmacao, a transacao precisa concluir antes de ser liberada.
  bool cancelar() {
    if (estado==PENDENTE || estado==APLICANDO || estado==CONCLUIDA) return false;
    estado=LIVRE; alterado=false; return true;
  }
  // Uso exclusivo da tarefa de Controle no estado APLICANDO.
  // Escreve todo o conjunto; Serial permanece impedida de editar nesta etapa.
  void aplicar() {
    for (uint8_t i=0; i<PARAM_COUNT; ++i) parametroEscrever(i,valores[i]);
  }
};
