/*
 * File: Controlador.c
 *
 * Code generated for Simulink model 'Controlador'.
 *
 * Model version                  : 1.34
 * Simulink Coder version         : 8.6 (R2014a) 27-Dec-2013
 * C/C++ source code generated on : Mon Nov 16 17:54:07 2026
 *
 * Target selection: ert.tlc
 * Embedded hardware selection: Atmel->AVR
 * Code generation objectives: Unspecified
 * Validation result: Not run
 */

#include "Controlador.h"
#include "Controlador_private.h"

/* Exported block parameters */
real_T hist_max = 0.5;                 /* Variable: hist_max
                                        * Referenced by: '<S1>/Relay'
                                        */
real_T hist_min = -0.5;                /* Variable: hist_min
                                        * Referenced by: '<S1>/Relay'
                                        */
real_T u_max = 12.0;                   /* Variable: u_max
                                        * Referenced by: '<S1>/Relay'
                                        */
real_T u_min = 0.0;                    /* Variable: u_min
                                        * Referenced by: '<S1>/Relay'
                                        */

/* Block states (auto storage) */
DW_Controlador_T Controlador_DW;

/* External inputs (root inport signals with auto storage) */
ExtU_Controlador_T Controlador_U;

/* External outputs (root outports fed by signals with auto storage) */
ExtY_Controlador_T Controlador_Y;

/* Real-time model */
RT_MODEL_Controlador_T Controlador_M_;
RT_MODEL_Controlador_T *const Controlador_M = &Controlador_M_;

/* Model step function */
void Controlador_step(void)
{
  real_T rtb_Relay;

  /* Sum: '<S1>/Erro' incorporates:
   *  Inport: '<Root>/Referencia'
   *  Inport: '<Root>/Temperatura'
   */
  rtb_Relay = Controlador_U.Referencia - Controlador_U.Temperatura;

  /* Relay: '<S1>/Relay' */
  if (rtb_Relay >= hist_max) {
    Controlador_DW.Relay_Mode = true;
  } else {
    if (rtb_Relay <= hist_min) {
      Controlador_DW.Relay_Mode = false;
    }
  }

  if (Controlador_DW.Relay_Mode) {
    /* Outport: '<Root>/U' */
    Controlador_Y.U = u_max;
  } else {
    /* Outport: '<Root>/U' */
    Controlador_Y.U = u_min;
  }

  /* End of Relay: '<S1>/Relay' */
}

/* Model initialize function */
void Controlador_initialize(void)
{
  /* Registration code */

  /* initialize error status */
  rtmSetErrorStatus(Controlador_M, (NULL));

  /* states (dwork) */
  (void) memset((void *)&Controlador_DW, 0,
                sizeof(DW_Controlador_T));

  /* external inputs */
  (void) memset((void *)&Controlador_U, 0,
                sizeof(ExtU_Controlador_T));

  /* external outputs */
  Controlador_Y.U = 0.0;
}

/* Model terminate function */
void Controlador_terminate(void)
{
  /* (no terminate code required) */
}

/*
 * File trailer for generated code.
 *
 * [EOF]
 */
