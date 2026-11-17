#pragma once
#include "modelo_selecionado.h"
#define PACOTE_ID "328856e577efcd11"
#define PARAM_COUNT 4
inline float parametroLer(unsigned char i) { switch(i) {
case 0: return (float)hist_max;
case 1: return (float)hist_min;
case 2: return (float)u_max;
case 3: return (float)u_min;
default: return 0; } }
inline bool parametroValido(unsigned char i,float v) { switch(i) {
case 0: return v>=1.000000000e-02f && v<=5.000000000e+00f;
case 1: return v>=-5.000000000e+00f && v<=-1.000000000e-02f;
case 2: return v>=0.000000000e+00f && v<=1.200000000e+01f;
case 3: return v>=0.000000000e+00f && v<=1.200000000e+01f;
default: return false; } }
inline void parametroEscrever(unsigned char i,float v) { switch(i) {
case 0: hist_max=v; break;
case 1: hist_min=v; break;
case 2: u_max=v; break;
case 3: u_min=v; break;
default: break; } }
