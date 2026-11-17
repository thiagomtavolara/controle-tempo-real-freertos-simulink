/*
 * File: Controlador.h
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

#ifndef RTW_HEADER_Controlador_h_
#define RTW_HEADER_Controlador_h_
#include <stddef.h>
#include <string.h>
#ifndef Controlador_COMMON_INCLUDES_
# define Controlador_COMMON_INCLUDES_
#include "rtwtypes.h"
#endif                                 /* Controlador_COMMON_INCLUDES_ */

#include "Controlador_types.h"

/* Macros for accessing real-time model data structure */
#ifndef rtmGetErrorStatus
# define rtmGetErrorStatus(rtm)        ((rtm)->errorStatus)
#endif

#ifndef rtmSetErrorStatus
# define rtmSetErrorStatus(rtm, val)   ((rtm)->errorStatus = (val))
#endif

#ifndef rtmGetStopRequested
# define rtmGetStopRequested(rtm)      ((void*) 0)
#endif

/* Block states (auto storage) for system '<Root>' */
typedef struct {
  boolean_T Relay_Mode;                /* '<S1>/Relay' */
} DW_Controlador_T;

/* External inputs (root inport signals with auto storage) */
typedef struct {
  real_T Referencia;                   /* '<Root>/Referencia' */
  real_T Temperatura;                  /* '<Root>/Temperatura' */
} ExtU_Controlador_T;

/* External outputs (root outports fed by signals with auto storage) */
typedef struct {
  real_T U;                            /* '<Root>/U' */
} ExtY_Controlador_T;

/* Real-time Model Data Structure */
struct tag_RTM_Controlador_T {
  const char_T *errorStatus;
};

/* Block states (auto storage) */
extern DW_Controlador_T Controlador_DW;

/* External inputs (root inport signals with auto storage) */
extern ExtU_Controlador_T Controlador_U;

/* External outputs (root outports fed by signals with auto storage) */
extern ExtY_Controlador_T Controlador_Y;

/*
 * Exported Global Parameters
 *
 * Note: Exported global parameters are tunable parameters with an exported
 * global storage class designation.  Code generation will declare the memory for
 * these parameters and exports their symbols.
 *
 */
extern real_T hist_max;                /* Variable: hist_max
                                        * Referenced by: '<S1>/Relay'
                                        */
extern real_T hist_min;                /* Variable: hist_min
                                        * Referenced by: '<S1>/Relay'
                                        */
extern real_T u_max;                   /* Variable: u_max
                                        * Referenced by: '<S1>/Relay'
                                        */
extern real_T u_min;                   /* Variable: u_min
                                        * Referenced by: '<S1>/Relay'
                                        */

/* Model entry point functions */
extern void Controlador_initialize(void);
extern void Controlador_step(void);
extern void Controlador_terminate(void);

/* Real-time Model object */
extern RT_MODEL_Controlador_T *const Controlador_M;

/*-
 * The generated code includes comments that allow you to trace directly
 * back to the appropriate location in the model.  The basic format
 * is <system>/block_name, where system is the system number (uniquely
 * assigned by Simulink) and block_name is the name of the block.
 *
 * Note that this particular code originates from a subsystem build,
 * and has its own system numbers different from the parent model.
 * Refer to the system hierarchy for this subsystem below, and use the
 * MATLAB hilite_system command to trace the generated code back
 * to the parent model.  For example,
 *
 * hilite_system('simulink_base_Bang_Bang/Controlador ')    - opens subsystem simulink_base_Bang_Bang/Controlador
 * hilite_system('simulink_base_Bang_Bang/Controlador /Kp') - opens and selects block Kp
 *
 * Here is the system hierarchy for this model
 *
 * '<Root>' : 'simulink_base_Bang_Bang'
 * '<S1>'   : 'simulink_base_Bang_Bang/Controlador '
 */
#endif                                 /* RTW_HEADER_Controlador_h_ */

/*
 * File trailer for generated code.
 *
 * [EOF]
 */
