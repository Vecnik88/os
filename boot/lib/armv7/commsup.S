/*++

Copyright (c) 2014 Minoca Corp.

    This file is licensed under the terms of the GNU General Public License
    version 3. Alternative licensing terms are available. Contact
    info@minocacorp.com for details. See the LICENSE file at the root of this
    project for complete licensing information.

Module Name:

    commsup.S

Abstract:

    This module implements assembly-based architecture support routines common
    to all ARM platforms.

Author:

    Chris Stevens 19-Mar-2014

Environment:

    Boot

--*/

//
// ------------------------------------------------------------------- Includes
//

#include <minoca/kernel/arm.inc>

//
// ---------------------------------------------------------------- Definitions
//

//
// ---------------------------------------------------------------------- Code
//

ASSEMBLY_FILE_HEADER

//
// VOID
// BoInitializeExceptionStacks (
//     PVOID ExceptionStacksBase,
//     ULONG ExceptionStackSize
//     )
//

/*++

Routine Description:

    This routine initializes the stack pointer for all privileged ARM modes. It
    switches into each mode and initializes the banked r13. This function
    should be called with interrupts disabled and returns with interrupts
    disabled.

Arguments:

    ExceptionStacksBase - Supplies a pointer to the lowest address that should
        be used for exception stacks. Each stack takes up 16 bytes and there are
        4 modes, so at least 64 bytes are needed.

    ExceptionStackSize - Supplies the size of each exception stack.

Return Value:

    None.

--*/

FUNCTION BoInitializeExceptionStacks

    //
    // Load R1 with an individual stack size.
    //

    add     %r0, %r0, %r1

    //
    // Disable interrupts and switch into IRQ mode. Note that this also
    // clobbers the flags register.
    //

    mov     %r2, #(PSR_FLAG_IRQ | ARM_MODE_IRQ)
    msr     CPSR_cxsf, %r2
    mov     %sp, %r0
    add     %r0, %r0, %r1

    //
    // Initialize the FIQ stack.
    //

    mov     %r2, #(PSR_FLAG_IRQ | ARM_MODE_FIQ)
    msr     CPSR_cxsf, %r2
    mov     %sp, %r0
    add     %r0, %r0, %r1

    //
    // Initialize the undefined instruction stack.
    //

    mov     %r2, #(PSR_FLAG_IRQ | ARM_MODE_UNDEF)
    msr     CPSR_cxsf, %r2
    mov     %sp, %r0
    add     %r0, %r0, %r1

    //
    // Initialize the data fetch abort stack.
    //

    mov     %r2, #(PSR_FLAG_IRQ | ARM_MODE_ABORT)
    msr     CPSR_cxsf, %r2
    mov     %sp, %r0

    //
    // Switch back to SVC mode and return.
    //

    mov     %r2, #(PSR_FLAG_IRQ | ARM_MODE_SVC)
    msr     CPSR_cxsf, %r2
    bx      %lr

END_FUNCTION BoInitializeExceptionStacks

//
// BOOL
// BoDisableInterrupts (
//     VOID
//     )
//

/*++

Routine Description:

    This routine disables all interrupts on the current processor.

Arguments:

    None.

Return Value:

    TRUE if interrupts were previously enabled on the processor.

    FALSE if interrupts were not previously enabled on the processor.

--*/

FUNCTION BoDisableInterrupts
    mrs     %r1, CPSR               @ Get the status register.
    cpsid   i                       @ Disable interrupts.
    mov     %r0, #0                 @ Assume interrupts disabled.
    tst     %r1, #PSR_FLAG_IRQ      @ AND the interrupt flag.
    IT(eq)                          @ If the zero flag is set...
    moveq   %r0, #1                 @ Interrupts were enabled.
    bx      %lr                     @ Return.

END_FUNCTION BoDisableInterrupts

//
// VOID
// BoEnableInterrupts (
//     VOID
//     )
//

/*++

Routine Description:

    This routine enables interrupts on the current processor.

Arguments:

    None.

Return Value:

    None.

--*/

FUNCTION BoEnableInterrupts
    mrs     %r0, CPSR               @ Get the status register.
    bic     %r0, %r0, #PSR_FLAG_IRQ @ Clear the interrupt bits.
    msr     CPSR_cxsf, %r0          @ Write the status register.
    bx      %lr                     @

END_FUNCTION BoEnableInterrupts

//
// BOOL
// BoAreInterruptsEnabled (
//     VOID
//     )
//

/*++

Routine Description:

    This routine determines whether or not interrupts are currently enabled
    on the processor.

Arguments:

    None.

Return Value:

    TRUE if interrupts are enabled in the processor.

    FALSE if interrupts are globally disabled.

--*/

FUNCTION BoAreInterruptsEnabled
    mrs     %r1, CPSR               @ Get the status register.
    mov     %r0, #0                 @ Assume interrupts disabled.
    tst     %r1, #PSR_FLAG_IRQ      @ AND the interrupt flag.
    IT(eq)                          @ If the zero flag is set...
    moveq   %r0, #1                 @ Interrupts were enabled.
    bx      %lr                     @ Return.

END_FUNCTION BoAreInterruptsEnabled

//
// VOID
// ArSerializeExecution (
//     VOID
//     )
//

/*++

Routine Description:

    This routine acts a serializing instruction, preventing the processor
    from speculatively executing beyond this point.

Arguments:

    None.

Return Value:

    None.

--*/

FUNCTION ArSerializeExecution
    DSB
    ISB
    bx      %lr

END_FUNCTION ArSerializeExecution

//
// VOID
// BoUndefinedInstructionEntry (
//     VOID
//     )
//

/*++

Routine Description:

    This routine directly handles an exception generated by an undefined
    instruction. It uses a largely separate code path from normal exceptions
    to avoid recursively breaking into the debugger.

Arguments:

    None.

Return Value:

    None.

--*/

FUNCTION BoUndefinedInstructionEntry

    //
    // Save state and create a trap frame.
    //

    ARM_ENTER_INTERRUPT

    //
    // Call the main dispatch routine routine with a pointer to the trap frame
    // as the only parameter.
    //

    mov     %r0, %sp
    bl      BopDispatchUndefinedInstructionException

    //
    // Restore state and return.
    //

    ARM_EXIT_INTERRUPT

END_FUNCTION BoUndefinedInstructionEntry

//
// VOID
// BoSoftwareInterruptEntry (
//     VOID
//     )
//

/*++

Routine Description:

    This routine directly handles an exception generated by a software
    interrupt (a system call).

Arguments:

    None.

Return Value:

    None.

--*/

FUNCTION BoSoftwareInterruptEntry
    b       BopCommonInterruptEntry     @ This is neither expected nor handled.

END_FUNCTION BoSoftwareInterruptEntry

//
// VOID
// BoPrefetchAbortEntry (
//     VOID
//     )
//

/*++

Routine Description:

    This routine directly handles an exception generated by a prefetch abort
    (page fault).

Arguments:

    None.

Return Value:

    None.

--*/

FUNCTION BoPrefetchAbortEntry
    sub     %lr, %lr, #4                @ Prefetches go too far by 4.

    //
    // Save state and create a trap frame.
    //

    ARM_ENTER_INTERRUPT

    //
    // Call the main dispatch routine routine with a pointer to the trap frame
    // and 1 to indicate a prefetch abort.
    //

    mov     %r0, %sp
    mov     %r1, #1
    blx     BopDispatchException

    //
    // Restore state and return.
    //

    ARM_EXIT_INTERRUPT

END_FUNCTION BoPrefetchAbortEntry

//
// VOID
// BoDataAbortEntry (
//     VOID
//     )
//

/*++

Routine Description:

    This routine directly handles an exception generated by a data abort (page
    fault).

Arguments:

    None.

Return Value:

    None.

--*/

FUNCTION BoDataAbortEntry
    sub     %lr, %lr, #8                @ Data aborts go too far by 8.

    //
    // Save state and create a trap frame.
    //

    ARM_ENTER_INTERRUPT

    //
    // Call the main dispatch routine routine with a pointer to the trap frame
    // and 0 to indicate a prefetch abort.
    //

    mov     %r0, %sp
    mov     %r1, #0
    blx     BopDispatchException

    //
    // Restore state and return.
    //

    ARM_EXIT_INTERRUPT

END_FUNCTION BoDataAbortEntry

//
// VOID
// BoIrqEntry (
//     VOID
//     )
//

/*++

Routine Description:

    This routine directly handles an exception generated by an external
    interrupt on the IRQ pin.

Arguments:

    None.

Return Value:

    None.

--*/

FUNCTION BoIrqEntry
    b       BopCommonInterruptEntry

END_FUNCTION BoIrqEntry

//
// VOID
// BoFiqEntry (
//     VOID
//     )
//

/*++

Routine Description:

    This routine directly handles an exception generated by an external
    interrupt on the FIQ pin.

Arguments:

    None.

Return Value:

    None.

--*/

FUNCTION BoFiqEntry
    b       BopCommonInterruptEntry

END_FUNCTION BoFiqEntry

//
// VOID
// BoCpuid (
//     PARM_CPUID Features
//     )
//

/*++

Routine Description:

    This routine returns the set of processor features present on the current
    processor.

Arguments:

    Features - Supplies a pointer where the processor feature register values
        will be returned.

Return Value:

    None.

--*/

FUNCTION BoCpuid
    mrc     p15, 0, %r1, c0, c1, 0              @ Get ID_PFR0.
    str     %r1, [%r0], #4                      @ Save it.
    mrc     p15, 0, %r1, c0, c1, 1              @ Get ID_PFR1.
    str     %r1, [%r0], #4                      @ Save it.
    mrc     p15, 0, %r1, c0, c1, 2              @ Get ID_DFR0.
    str     %r1, [%r0], #4                      @ Save it.
    mrc     p15, 0, %r1, c0, c1, 3              @ Get ID_AFR0.
    str     %r1, [%r0], #4                      @ Save it.
    mrc     p15, 0, %r1, c0, c1, 4              @ Get ID_MMFR0.
    str     %r1, [%r0], #4                      @ Save it.
    mrc     p15, 0, %r1, c0, c1, 5              @ Get ID_MMFR1.
    str     %r1, [%r0], #4                      @ Save it.
    mrc     p15, 0, %r1, c0, c1, 6              @ Get ID_MMFR2.
    str     %r1, [%r0], #4                      @ Save it.
    mrc     p15, 0, %r1, c0, c1, 7              @ Get ID_MMFR3.
    str     %r1, [%r0], #4                      @ Save it.
    mrc     p15, 0, %r1, c0, c2, 0              @ Get ID_IDAR0.
    str     %r1, [%r0], #4                      @ Save it.
    mrc     p15, 0, %r1, c0, c2, 1              @ Get ID_IDAR1.
    str     %r1, [%r0], #4                      @ Save it.
    mrc     p15, 0, %r1, c0, c2, 2              @ Get ID_IDAR2.
    str     %r1, [%r0], #4                      @ Save it.
    mrc     p15, 0, %r1, c0, c2, 3              @ Get ID_IDAR3.
    str     %r1, [%r0], #4                      @ Save it.
    mrc     p15, 0, %r1, c0, c2, 4              @ Get ID_IDAR4.
    str     %r1, [%r0], #4                      @ Save it.
    mrc     p15, 0, %r1, c0, c2, 5              @ Get ID_IDAR5.
    str     %r1, [%r0], #4                      @ Save it.
    bx      %lr                                 @ Return!

END_FUNCTION BoCpuid

//
// ULONG
// ArGetSystemControlRegister (
//     VOID
//     )
//

/*++

Routine Description:

    This routine returns the MMU system control register (SCTLR).

Arguments:

    None.

Return Value:

    Returns the current SCTLR value.

--*/

FUNCTION ArGetSystemControlRegister
    mrc     p15, 0, %r0, %cr1, %cr0, 0          @ Get the SCTLR.
    bx      %lr                                 @ Return.

END_FUNCTION ArGetSystemControlRegister

//
// VOID
// ArSetSystemControlRegister (
//     ULONG NewValue
//     )
//

/*++

Routine Description:

    This routine sets the MMU system control register (SCTLR).

Arguments:

    NewValue - Supplies the value to set as the new MMU SCTLR.

Return Value:

    None.

--*/

FUNCTION ArSetSystemControlRegister
    mcr     p15, 0, %r0, %cr1, %cr0, 0          @ Set the SCTLR.
    bx      %lr                                 @ Return.

END_FUNCTION ArSetSystemControlRegister

//
// ULONG
// ArGetAuxiliaryControlRegister (
//     VOID
//     )
//

/*++

Routine Description:

    This routine returns the auxiliary system control register (ACTLR).

Arguments:

    None.

Return Value:

    Returns the current value.

--*/

FUNCTION ArGetAuxiliaryControlRegister
    mrc     p15, 0, %r0, %cr1, %cr0, 1
    bx      %lr

END_FUNCTION ArGetAuxiliaryControlRegister

//
// VOID
// ArSetAuxiliaryControlRegister (
//     ULONG NewValue
//     )
//

/*++

Routine Description:

    This routine sets the auxiliary system control register (ACTLR).

Arguments:

    NewValue - Supplies the value to set.

Return Value:

    None.

--*/

FUNCTION ArSetAuxiliaryControlRegister
    mcr     p15, 0, %r0, %cr1, %cr0, 1
    bx      %lr

END_FUNCTION ArSetAuxiliaryControlRegister

//
// PVOID
// ArGetVectorBaseAddress (
//     VOID
//     )
//

/*++

Routine Description:

    This routine gets the vector base address register (VBAR) which determines
    where the ARM exception vector table starts.

Arguments:

    None.

Return Value:

    Returns the current VBAR.

--*/

FUNCTION ArGetVectorBaseAddress
    mrc     p15, 0, %r0, c12, c0, 0
    bx      %lr

END_FUNCTION ArGetVectorBaseAddress

//
// VOID
// ArSetVectorBaseAddress (
//     PVOID VectorBaseAddress
//     )
//

/*++

Routine Description:

    This routine sets the vector base address register (VBAR) which determines
    where the ARM exception vector table starts.

Arguments:

    VectorBaseAddress - Supplies a pointer to the ARM exception vector base
        address. This value must be 32-byte aligned.

Return Value:

    None.

--*/

FUNCTION ArSetVectorBaseAddress
    mcr     p15, 0, %r0, c12, c0, 0             @ Set VBAR.
    bx      %lr                                 @ Return.

END_FUNCTION ArSetVectorBaseAddress

//
// PVOID
// ArGetDataFaultingAddress (
//     VOID
//     )
//

/*++

Routine Description:

    This routine determines which address caused a data abort.

Arguments:

    None.

Return Value:

    Returns the faulting address.

--*/

FUNCTION ArGetDataFaultingAddress
    mrc     p15, 0, %r0, %cr6, %cr0, 0          @ Get the combined/data FAR.
    bx      %lr                                 @

END_FUNCTION ArGetDataFaultingAddress

//
// VOID
// ArSetDataFaultingAddress (
//     PVOID Value
//     )
//

/*++

Routine Description:

    This routine sets the data faulting address register (DFAR).

Arguments:

    Value - Supplies the value to set.

Return Value:

    None.

--*/

FUNCTION ArSetDataFaultingAddress
    mcr     p15, 0, %r0, %cr6, %cr0, 0
    bx      %lr

END_FUNCTION ArSetDataFaultingAddress

//
// PVOID
// ArGetInstructionFaultingAddress (
//     VOID
//     )
//

/*++

Routine Description:

    This routine determines which address caused a prefetch abort.

Arguments:

    None.

Return Value:

    Returns the faulting address.

--*/

FUNCTION ArGetInstructionFaultingAddress
    mrc     p15, 0, %r0, %cr6, %cr0, 2          @ Get the IFAR.
    bx      %lr                                 @

END_FUNCTION ArGetInstructionFaultingAddress

//
// VOID
// ArSetInstructionFaultingAddress (
//     PVOID Value
//     )
//

/*++

Routine Description:

    This routine sets the instruction faulting address register (IFAR).

Arguments:

    Value - Supplies the value to set.

Return Value:

    None.

--*/

FUNCTION ArSetInstructionFaultingAddress
    mcr     p15, 0, %r0, %cr6, %cr0, 2
    bx      %lr

END_FUNCTION ArSetInstructionFaultingAddress

//
// ULONG
// ArGetDataFaultStatus (
//     VOID
//     )
//

/*++

Routine Description:

    This routine determines the reason for the fault by reading the DFSR
    register.

Arguments:

    None.

Return Value:

    Returns the contents of the Data Fault Status Register.

--*/

FUNCTION ArGetDataFaultStatus
    mrc     p15, 0, %r0, %cr5, %cr0, 0          @ Get the DFSR.
    bx      %lr                                 @

END_FUNCTION ArGetDataFaultStatus

//
// VOID
// ArSetDataFaultStatus (
//     ULONG Value
//     )
//

/*++

Routine Description:

    This routine sets the data fault status register (DFSR).

Arguments:

    Value - Supplies the value to set.

Return Value:

    None.

--*/

FUNCTION ArSetDataFaultStatus
    mcr     p15, 0, %r0, %cr5, %cr0, 0
    bx      %lr

END_FUNCTION ArSetDataFaultStatus

//
// ULONG
// ArGetInstructionFaultStatus (
//     VOID
//     )
//

/*++

Routine Description:

    This routine determines the reason for the prefetch abort by reading the
    IFAR register.

Arguments:

    None.

Return Value:

    Returns the contents of the Instruction Fault Status Register.

--*/

FUNCTION ArGetInstructionFaultStatus
    mrc     p15, 0, %r0, %cr5, %cr0, 1          @ Get the IFSR.
    bx      %lr                                 @

END_FUNCTION ArGetInstructionFaultStatus

//
// VOID
// ArSetInstructionFaultStatus (
//     ULONG Value
//     )
//

/*++

Routine Description:

    This routine sets the instruction fault status register (IFSR).

Arguments:

    Value - Supplies the value to set.

Return Value:

    None.

--*/

FUNCTION ArSetInstructionFaultStatus
    mcr     p15, 0, %r0, %cr5, %cr0, 1
    bx      %lr

END_FUNCTION ArSetInstructionFaultStatus

//
// PVOID
// ArGetProcessorBlockRegister (
//     VOID
//     )
//

/*++

Routine Description:

    This routine gets the register used to store a pointer to the processor
    block (TPIDRPRW in the ARMARM; Thread and Process ID Registers in the
    ARM1176 TRM).

Arguments:

    None.

Return Value:

    Returns a pointer to the processor block.

--*/

FUNCTION ArGetProcessorBlockRegister
    mrc     p15, 0, %r0, c13, c0, 4             @ Get TPIDRPRW.
    bx      %lr                                 @ Return.

END_FUNCTION ArGetProcessorBlockRegister

//
// VOID
// ArSetProcessorBlockRegister (
//     PVOID ProcessorBlockRegisterValue
//     )
//

/*++

Routine Description:

    This routine sets the register used to store a pointer to the processor
    block (TPIDRPRW in the ARMARM; Thread and Process ID Registers in the
    ARM1176 TRM).

Arguments:

    ProcessorBlockRegisterValue - Supplies the value to assign to the register
        used to store the processor block.

Return Value:

    None.

--*/

FUNCTION ArSetProcessorBlockRegister
    mcr     p15, 0, %r0, c13, c0, 4             @ Set TPIDRPRW.
    bx      %lr                                 @ Return.

END_FUNCTION ArSetProcessorBlockRegister

//
// ULONG
// ArGetTranslationTableBaseRegister0 (
//     VOID
//     )
//

/*++

Routine Description:

    This routine gets the translation table base register 0 (TTBR0), used as
    the base for all virtual to physical memory lookups.

Arguments:

    None.

Return Value:

    Returns the contents of TTBR0.

--*/

FUNCTION ArGetTranslationTableBaseRegister0
    mrc     p15, 0, %r0, c2, c0, 0              @ Get TTBR0.
    bx      %lr                                 @ Return.

END_FUNCTION ArGetTranslationTableBaseRegister0

//
// VOID
// ArSetTranslationTableBaseRegister0 (
//     ULONG Value
//     )
//

/*++

Routine Description:

    This routine sets the translation table base register 0 (TTBR0).

Arguments:

    Value - Supplies the value to write.

Return Value:

    None.

--*/

FUNCTION ArSetTranslationTableBaseRegister0
    mcr     p15, 0, %r0, c2, c0, 0
    bx      %lr

END_FUNCTION ArSetTranslationTableBaseRegister0

//
// ULONG
// ArGetTranslationTableBaseRegister1 (
//     VOID
//     )
//

/*++

Routine Description:

    This routine gets the translation table base register 1 (TTBR1).

Arguments:

    None.

Return Value:

    Returns the contents of TTBR1.

--*/

FUNCTION ArGetTranslationTableBaseRegister1
    mrc     p15, 0, %r0, c2, c0, 1
    bx      %lr

END_FUNCTION ArGetTranslationTableBaseRegister1

//
// VOID
// ArSetTranslationTableBaseRegister1 (
//     ULONG Value
//     )
//

/*++

Routine Description:

    This routine sets the translation table base register 1 (TTBR1).

Arguments:

    Value - Supplies the value to write.

Return Value:

    None.

--*/

FUNCTION ArSetTranslationTableBaseRegister1
    mcr     p15, 0, %r0, c2, c0, 1
    bx      %lr

END_FUNCTION ArSetTranslationTableBaseRegister1

//
// ULONG
// ArGetPrimaryRegionRemapRegister (
//     VOID
//     )
//

/*++

Routine Description:

    This routine gets the Primary Region Remap Register (PRRR).

Arguments:

    None.

Return Value:

    Returns the contents of the register.

--*/

FUNCTION ArGetPrimaryRegionRemapRegister
    mrc     p15, 0, %r0, c10, c2, 0
    bx      %lr

END_FUNCTION ArGetPrimaryRegionRemapRegister

//
// VOID
// ArSetPrimaryRegionRemapRegister (
//     ULONG Value
//     )
//

/*++

Routine Description:

    This routine sets the PRRR.

Arguments:

    Value - Supplies the value to write.

Return Value:

    None.

--*/

FUNCTION ArSetPrimaryRegionRemapRegister
    mcr     p15, 0, %r0, c10, c2, 0
    bx      %lr

END_FUNCTION ArSetPrimaryRegionRemapRegister

//
// ULONG
// ArGetNormalMemoryRemapRegister (
//     VOID
//     )
//

/*++

Routine Description:

    This routine gets the Normal Memory Remap Register (NMRR).

Arguments:

    None.

Return Value:

    Returns the contents of the register.

--*/

FUNCTION ArGetNormalMemoryRemapRegister
    mrc     p15, 0, %r0, c10, c2, 1
    bx      %lr

END_FUNCTION ArGetNormalMemoryRemapRegister

//
// VOID
// ArSetNormalMemoryRemapRegister (
//     ULONG Value
//     )
//

/*++

Routine Description:

    This routine sets the NMRR.

Arguments:

    Value - Supplies the value to write.

Return Value:

    None.

--*/

FUNCTION ArSetNormalMemoryRemapRegister
    mcr     p15, 0, %r0, c10, c2, 1
    bx      %lr

END_FUNCTION ArSetNormalMemoryRemapRegister

//
// ULONG
// ArGetPhysicalAddressRegister (
//     VOID
//     )
//

/*++

Routine Description:

    This routine gets the Physical Address Register (PAR).

Arguments:

    None.

Return Value:

    Returns the contents of the register.

--*/

FUNCTION ArGetPhysicalAddressRegister
    mrc     p15, 0, %r0, c7, c4, 0
    bx      %lr

END_FUNCTION ArGetPhysicalAddressRegister

//
// VOID
// ArSetPhysicalAddressRegister (
//     ULONG Value
//     )
//

/*++

Routine Description:

    This routine sets the Physical Address Register (PAR).

Arguments:

    Value - Supplies the value to write.

Return Value:

    None.

--*/

FUNCTION ArSetPhysicalAddressRegister
    mcr     p15, 0, %r0, c7, c4, 0
    bx      %lr

END_FUNCTION ArSetPhysicalAddressRegister

//
// VOID
// ArSetPrivilegedReadTranslateRegister (
//     ULONG Value
//     )
//

/*++

Routine Description:

    This routine sets the Privileged Read address translation command register.

Arguments:

    Value - Supplies the value to write.

Return Value:

    None.

--*/

FUNCTION ArSetPrivilegedReadTranslateRegister
    mcr     p15, 0, %r0, c7, c8, 0
    bx      %lr

END_FUNCTION ArSetPrivilegedReadTranslateRegister

//
// VOID
// ArSetPrivilegedWriteTranslateRegister (
//     ULONG Value
//     )
//

/*++

Routine Description:

    This routine sets the Privileged Write address translation command register.

Arguments:

    Value - Supplies the value to write.

Return Value:

    None.

--*/

FUNCTION ArSetPrivilegedWriteTranslateRegister
    mcr     p15, 0, %r0, c7, c8, 1
    bx      %lr

END_FUNCTION ArSetPrivilegedWriteTranslateRegister

//
// VOID
// ArSetUnprivilegedReadTranslateRegister (
//     ULONG Value
//     )
//

/*++

Routine Description:

    This routine sets the Unrivileged Read address translation command register.

Arguments:

    Value - Supplies the value to write.

Return Value:

    None.

--*/

FUNCTION ArSetUnprivilegedReadTranslateRegister
    mcr     p15, 0, %r0, c7, c8, 2
    bx      %lr

END_FUNCTION ArSetUnprivilegedReadTranslateRegister

//
// VOID
// ArSetUnprivilegedWriteTranslateRegister (
//     ULONG Value
//     )
//

/*++

Routine Description:

    This routine sets the Unprivileged Write address translation command
    register.

Arguments:

    Value - Supplies the value to write.

Return Value:

    None.

--*/

FUNCTION ArSetUnprivilegedWriteTranslateRegister
    mcr     p15, 0, %r0, c7, c8, 3
    bx      %lr

END_FUNCTION ArSetUnprivilegedWriteTranslateRegister

//
// --------------------------------------------------------- Internal Functions
//

//
// This code is entered as the result of any interrupt or exception. Its job is
// to transition back to the SVC stack and then call the real interrupt
// dispatch routine.
//

FUNCTION BopCommonInterruptEntry

    //
    // Save state and create a trap frame.
    //

    ARM_ENTER_INTERRUPT

    //
    // Call the main dispatch routine routine with a pointer to the trap frame
    // as the only parameter.
    //

    mov     %r0, %sp
    bl      BopDispatchException

    //
    // Restore state and return.
    //

    ARM_EXIT_INTERRUPT

END_FUNCTION BopCommonInterruptEntry

