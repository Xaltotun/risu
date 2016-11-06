/*****************************************************************************
 * Copyright (c) IBM Corp, 2016
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *
 * Contributors:
 *     Jose Ricardo Ziviani - ppc64le implementation
 *     based on Claudio Fontana
 *     based on test_arm.s by Peter Maydell
 *****************************************************************************/

/* Initialise the gp regs */
li 0,0
li 1,1
li 2,2
li 3,3
li 4,4
li 5,5
li 6,6
li 7,7
li 8,8
li 9,9
li 10, 10
li 11, 11
li 12, 12
li 13, 13
li 14, 14
li 15, 15
li 16, 16
li 17, 17
li 18, 18
li 19, 19
li 20, 20
li 21, 21
li 22, 22
li 23, 23
li 24, 24
li 25, 25
li 26, 26
li 27, 27
li 28, 28
li 29, 29
li 30, 30
li 31, 31

/* do compare */
.int 0x00005af0
/* exit test */
.int 0x00005af1
