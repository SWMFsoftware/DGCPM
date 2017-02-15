!  Copyright (C) 2002 Regents of the University of Michigan, portions used with permission 
!  For more information, see http://csem.engin.umich.edu/tools/swmf
! File name: dgcpm_coefficients_010.f9
!
! Contains: drift and diffusion coefficient definition routines for DGCPM
!	MAGCONV
!
! Last Modified: December 2006, Mike Liemohn
!
! **********************************************************************
!                             MAGCONV
!	Calculates magnetospheric convection strength and puts it
!	into the drift terms 
!	(added to already-calculated corotation and gradient-curvature)
! **********************************************************************
SUBROUTINE MAGCONV

  use ModSizeDGCPM
  use ModMainDGCPM
  use ModIoDGCPM
  use ModConstants

  implicit none

  integer j,i

  !  Calculate base convection electric field
  !  CC Shielded Volland-Stern

  do J=1,nphicells   ! Fill in DGCPM potentials
!     write(*,*) j, vphicells(j)
     do I=1,nthetacells
!        if (j == nphicells) write(*,*) i, vlzcells(i)
        mgridpot(i,j)=a*re*vlzcells(i)**(lamgam)*sin(dtor*vphicells(J))
     enddo
  enddo

  if (debug .gt. 0) write(*,*) "cpcp : ", maxval(mgridpot)-minval(mgridpot)

end subroutine magconv
!
! End of subroutine MAGCONV
!
