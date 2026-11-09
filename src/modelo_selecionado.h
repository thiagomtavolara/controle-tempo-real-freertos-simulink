#pragma once
extern "C" {
#include "gerado/Controlador.h"
}
#define MODELO_INICIAR Controlador_initialize
#define MODELO_PASSO Controlador_step
#define MODELO_ENTRADAS Controlador_U
#define MODELO_SAIDAS Controlador_Y
#define MODELO_PERIODO_S 2.000000000e-01f
