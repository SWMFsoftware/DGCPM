Module ModHeidiCurrents
  !\
  ! Current and potential variable definition module for the HEIDI program.
  ! Mike Liemohn, March 2006
  !/

	use ModHeidiSize

! Define variables for current densities
! Formerly: Common block CURRENTS
	real, dimension(NR+3) :: Lsh, Lats
	real, dimension(NR+3,NT,NS) :: Iphi,Irad,Jion1
	real, dimension(NR+3,NT) :: BASEPOT
!	real Lsh(NR+3),Lats(NR+3),Iphi(NR+3,NT,NS),Irad(NR+3,NT,NS)
!	real Jion1(NR+3,NT,NS),BASEPOT(NR+3,NT)
	integer Ir

! Define variables for FAC-driven electric potential
! Formerly: Common block FACPOT
	real Latfac(NR+3),Lonfac(NT),Jfac(NR+3,NT),FPOT(NR+3,NT)
	integer Irfac, Ilfac

! Define variables for plasma pressure and other bulk quantities
! Formerly:  Common block CPRESS
	real PPER(NR,NT,NS),PPAR(NR,NT,NS),RNHT(NR,NT,NS)
	real EDEN(NR,NT,NS),ANIS(NR,NT,NS),EPAR(NR,NT,NS),Dst(NS)
	real NTOT(NS),ETOT(NS),JPER(NR,NT,NS)
	real Nspace(NR,NT,NS),Espace(NR,NT,NS)

! Define variables for the current calculation procedure
! Formerly:  Common block CURCALC
	real rl(NR+3,Slen),drl(NR+3,Slen),r2(3,NR+3,NT,Slen)
	real dBdrB(3,NR+3,NT,Slen),Rxy(NR+3,Slen),Bz(NR+3,Slen)
	real Bxy(NR+3,Slen),Bf2(NR+3,Slen),ds1(NR+3,Slen),ds2(NR+3,Slen)
	real ds(NR+3,Slen),beta1(NR+3,Slen),beta2(NR+3,Slen)
	real alpha1(NR+3,Slen),delR(NR+3,Slen),gam1(NT),gam2(NT)
	real dRm(NR+3),dR1(NR+3,Slen),dR2(NR+3,Slen),sp(NT),cp(NT)
	real sr(NR+3,Slen),cr(NR+3,Slen),sr3(NR+3,Slen),BBr(NR+3,Slen)
	real sl(NR+3),cl(NR+3),fac1(NR+3,Slen),fac2(NR+3,Slen)
	
! Define variables for the trig functions in the current calculation
! Formerly:  Common block CURTRIG
	real sg1(NT),sg2(NT),cg1(NT),cg2(NT),sb1(NR+3,Slen)
	real sb2(NR+3,Slen),cb1(NR+3,Slen),cb2(NR+3,Slen),sa1(NR+3,Slen)
	real ca1(NR+3,Slen)

! Define variables for the indexing counters in the current calculation
! Formerly: Common block CURINTS
	integer Ko2,Kmax(NR+3),j1(NT),j2(NT),i1(NR+3),i2(NR+3)
	integer k1(NR+3,Slen),k2(NR+3,Slen),ikk1(NR+3,Slen),ikk2(NR+3,Slen)
	integer ik1(NR+3,Slen),ik2(NR+3,Slen)

end Module ModHeidiCurrents
