/*
 * File: Controlador.c
 *
 * Code generated for Simulink model 'Controlador'.
 *
 * Model version                  : 1.36
 * Simulink Coder version         : 8.6 (R2014a) 27-Dec-2013
 * C/C++ source code generated on : Sun Nov 08 18:48:00 2026
 *
 * Target selection: ert.tlc
 * Embedded hardware selection: Atmel->AVR
 * Code generation objectives: Unspecified
 * Validation result: Not run
 */

#include "Controlador.h"
#include "Controlador_private.h"

/* Exported block parameters */
real_T D = 0.2;                        /* Variable: D
                                        * Referenced by: '<S2>/Derivative Gain'
                                        */
real_T I = 1.0;                        /* Variable: I
                                        * Referenced by: '<S2>/Integral Gain'
                                        */
real_T N = 5.0;                        /* Variable: N
                                        * Referenced by: '<S2>/Filter Coefficient'
                                        */
real_T P = 3.0;                        /* Variable: P
                                        * Referenced by: '<S2>/Proportional Gain'
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
  real_T rtb_Sum;
  real_T rtb_IntegralGain;
  real_T rtb_ProportionalGain;
  real_T rtb_FilterCoefficient;
  boolean_T rtb_Equal1;
  boolean_T rtb_Equal2;
  real_T rtb_DeadZone;
  real_T rtb_DeadZone_0;
  real_T rtb_IntegralGain_0;

  /* Sum: '<S1>/Erro' incorporates:
   *  Inport: '<Root>/Referencia'
   *  Inport: '<Root>/Temperatura'
   */
  rtb_IntegralGain = Controlador_U.Referencia - Controlador_U.Temperatura;

  /* Gain: '<S2>/Filter Coefficient' incorporates:
   *  DiscreteIntegrator: '<S2>/Filter'
   *  Gain: '<S2>/Derivative Gain'
   *  Sum: '<S2>/SumD'
   */
  rtb_FilterCoefficient = (D * rtb_IntegralGain - Controlador_DW.Filter_DSTATE) *
    N;

  /* Sum: '<S2>/Sum' incorporates:
   *  DiscreteIntegrator: '<S2>/Integrator'
   */
  rtb_Sum = (rtb_IntegralGain + Controlador_DW.Integrator_DSTATE) +
    rtb_FilterCoefficient;

  /* Gain: '<S2>/Proportional Gain' */
  rtb_ProportionalGain = P * rtb_Sum;

  /* Saturate: '<S2>/Saturation' */
  if (rtb_ProportionalGain > 12.0) {
    /* Outport: '<Root>/U' */
    Controlador_Y.U = 12.0;
  } else if (rtb_ProportionalGain < 0.0) {
    /* Outport: '<Root>/U' */
    Controlador_Y.U = 0.0;
  } else {
    /* Outport: '<Root>/U' */
    Controlador_Y.U = rtb_ProportionalGain;
  }

  /* End of Saturate: '<S2>/Saturation' */

  /* Gain: '<S2>/Integral Gain' */
  rtb_IntegralGain *= I;

  /* DeadZone: '<S3>/DeadZone' */
  if (rtb_ProportionalGain > 12.0) {
    rtb_DeadZone = rtb_ProportionalGain - 12.0;
  } else if (rtb_ProportionalGain >= 0.0) {
    rtb_DeadZone = 0.0;
  } else {
    rtb_DeadZone = rtb_ProportionalGain;
  }

  /* End of DeadZone: '<S3>/DeadZone' */

  /* Signum: '<S3>/SignDeltaU' */
  if (rtb_DeadZone < 0.0) {
    rtb_DeadZone_0 = -1.0;
  } else if (rtb_DeadZone > 0.0) {
    rtb_DeadZone_0 = 1.0;
  } else {
    rtb_DeadZone_0 = rtb_DeadZone;
  }

  /* Signum: '<S3>/SignPreIntegrator' */
  if (rtb_IntegralGain < 0.0) {
    rtb_IntegralGain_0 = -1.0;
  } else if (rtb_IntegralGain > 0.0) {
    rtb_IntegralGain_0 = 1.0;
  } else {
    rtb_IntegralGain_0 = rtb_IntegralGain;
  }

  /* RelationalOperator: '<S3>/Equal1' incorporates:
   *  Signum: '<S3>/SignDeltaU'
   *  Signum: '<S3>/SignPreIntegrator'
   */
  rtb_Equal1 = (rtb_DeadZone_0 == rtb_IntegralGain_0);

  /* Signum: '<S3>/SignPreSat' */
  if (rtb_ProportionalGain < 0.0) {
    rtb_ProportionalGain = -1.0;
  } else {
    if (rtb_ProportionalGain > 0.0) {
      rtb_ProportionalGain = 1.0;
    }
  }

  /* Signum: '<S3>/SignPreP' */
  if (rtb_Sum < 0.0) {
    rtb_Sum = -1.0;
  } else {
    if (rtb_Sum > 0.0) {
      rtb_Sum = 1.0;
    }
  }

  /* RelationalOperator: '<S3>/Equal2' incorporates:
   *  Signum: '<S3>/SignPreP'
   *  Signum: '<S3>/SignPreSat'
   */
  rtb_Equal2 = (rtb_ProportionalGain == rtb_Sum);

  /* Switch: '<S2>/Switch' incorporates:
   *  Constant: '<S2>/Constant'
   *  Gain: '<S3>/Gain'
   *  Logic: '<S3>/AND1'
   *  Logic: '<S3>/AND2'
   *  Logic: '<S3>/AND3'
   *  Logic: '<S3>/NOT1'
   *  Logic: '<S3>/NOT2'
   *  Logic: '<S3>/OR1'
   *  RelationalOperator: '<S3>/NotEqual'
   */
  if ((0.0 != rtb_DeadZone) && ((rtb_Equal1 && rtb_Equal2) || ((!rtb_Equal1) &&
        (!rtb_Equal2)))) {
    rtb_IntegralGain = 0.0;
  }

  /* End of Switch: '<S2>/Switch' */

  /* Update for DiscreteIntegrator: '<S2>/Integrator' */
  Controlador_DW.Integrator_DSTATE += 0.2 * rtb_IntegralGain;

  /* Update for DiscreteIntegrator: '<S2>/Filter' */
  Controlador_DW.Filter_DSTATE += 0.2 * rtb_FilterCoefficient;
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
