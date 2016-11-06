/******************************************************************************
 * Copyright (c) IBM Corp, 2016
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *
 * Contributors:
 *     Jose Ricardo Ziviani - initial implementation
 *     based on Claudio Fontana's risu_reginfo_aarch64
 *     based on Peter Maydell's risu_arm.c
 *****************************************************************************/

#ifndef RISU_REGINFO_PPC64LE_H
#define RISU_REGINFO_PPC64LE_H

struct reginfo
{
    uint32_t faulting_insn;
    uint32_t prev_insn;
    uint64_t nip;
    uint64_t prev_addr;
    gregset_t gregs;
    fpregset_t fpregs;
    vrregset_t vrregs;
};

/* initialize structure from a ucontext */
void reginfo_init(struct reginfo *ri, ucontext_t *uc);

/* return 1 if structs are equal, 0 otherwise. */
int reginfo_is_eq(struct reginfo *r1, struct reginfo *r2, ucontext_t *uc);

/* print reginfo state to a stream */
void reginfo_dump(struct reginfo *ri, int is_master);

/* reginfo_dump_mismatch: print mismatch details to a stream, ret nonzero=ok */
int reginfo_dump_mismatch(struct reginfo *m, struct reginfo *a, FILE *f);

#endif /* RISU_REGINFO_PPC64LE_H */
