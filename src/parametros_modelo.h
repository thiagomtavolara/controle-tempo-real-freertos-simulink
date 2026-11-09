#pragma once
#include "modelo_selecionado.h"
#define PACOTE_ID "42e6c08e5a7c665d"
#define PARAM_COUNT 4
inline float parametroLer(unsigned char i) { switch(i) {
case 0: return (float)D;
case 1: return (float)I;
case 2: return (float)N;
case 3: return (float)P;
default: return 0; } }
inline bool parametroValido(unsigned char i,float v) { switch(i) {
case 0: return v>=0.000000000e+00f && v<=1.000000000e+01f;
case 1: return v>=0.000000000e+00f && v<=2.000000000e+01f;
case 2: return v>=0.000000000e+00f && v<=1.000000000e+02f;
case 3: return v>=0.000000000e+00f && v<=1.000000000e+02f;
default: return false; } }
inline void parametroEscrever(unsigned char i,float v) { switch(i) {
case 0: D=v; break;
case 1: I=v; break;
case 2: N=v; break;
case 3: P=v; break;
default: break; } }
