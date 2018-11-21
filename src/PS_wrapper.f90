!  Copyright (C) 2002 Regents of the University of Michigan, 
!  portions used with permission 
!  For more information, see http://csem.engin.umich.edu/tools/swmf

module PS_wrapper

  ! Wrapper for DGCPM Plasmasphere Model

  implicit none

  private ! except
 
  public:: PS_set_param
  public:: PS_init_session
  public:: PS_run
  public:: PS_save_restart
  public:: PS_finalize

  ! coupling with IE
  public:: PS_put_from_ie

  ! coupling with GM
  public:: PS_get_for_gm
  
contains

  !===========================================================================

  subroutine PS_set_param(CompInfo, TypeAction)

    use ModProcPS
    use ModMainDGCPM
    use ModIoDGCPM
    use ModTimeDGCPM,  ONLY: MaxTime
    use CON_physics,   ONLY: get_time
    use CON_TIME,      ONLY: tSimulationMax
    use ModIoUnit
    use CON_comp_info

    ! Arguments
    type(CompInfoType), intent(inout):: CompInfo   ! Information for this comp.
    character (len=*), intent(in)    :: TypeAction ! What to do

    integer :: iError

    character (len=*), parameter :: NameSub='PS_set_param'
    logical                      :: DoTest, DoTestMe
    !-------------------------------------------------------------------------
    call CON_set_do_test(NameSub, DoTest, DoTestMe)
    
    select case(TypeAction)
    case('VERSION')
       call put(CompInfo,&
            Use=.true.,                                    &
            NameVersion='Dynamic Global Core Plasma Model (DGCPM)',&
            Version=0.1)
    case('MPI')
       call get(CompInfo, iComm=iComm, iProc=iProc, nProc=nProc)
       if(nProc>1)  call CON_stop(NameSub//' PS_ERROR this version is serial!')
    case('READ','CHECK')
       call read_param
    case('STDOUT')
       iUnitOut=STDOUT_
       if(nProc==1)then
          StringPrefix='PS:'
       else
          write(StringPrefix,'(a,i1,a)')'PS',iProc,':'
       end if
    case('FILEOUT')
       call get(CompInfo,iUnitOut=iUnitOut)
       StringPrefix=''
    case('GRID')
       call PS_set_grid
    case default
       call CON_stop(NameSub//' PS_ERROR: invalid TypeAction='//TypeAction)
    end select

  contains
    !==========================================================================
    subroutine read_param

      use ModReadParam
      use ModUtilities,   ONLY: fix_dir_name, check_dir, lower_case
      use ModCoupleDGCPM, ONLY: iGmFluidCouple, TempPlas
      ! The name of the command
      character (len=100) :: NameCommand

      ! Read parameters
      logical :: DoEcho=.false., UseStrict=.true.

      ! Plot file parameters
      integer :: iFile, i, iError, iDebugProc
      character (len=50) :: plot_string
      character (len=100) :: imffilename, kpfilename
      character (len=100), dimension(100) :: cTempLines
      real :: tmax

      !------------------------------------------------------------------------
      select case(TypeAction)
      case('CHECK')
         ! We should check and correct parameters here
         if(iProc==0)write(*,*) NameSub,': CHECK iSession =',i_session_read()
         RETURN

      case('READ')
         if(iProc==0)write(*,*) NameSub,': READ iSession =',i_session_read(),&
              ' iLine=',i_line_read(),' nLine =',n_line_read()
      end select

      ! Read Input Data from Text via ModReadParam
      do
         if(.not.read_line() ) EXIT
         if(.not.read_command(NameCommand)) CYCLE

         select case(NameCommand)
         case("#TIMESTEP")
            call read_var('DtStep', DT)

         case("#TIMING")
            call read_var('DtStep',DT)
            call read_var('TMAX', Tmax)

         case("#KP")
            call read_var('NameSourceKp', NameSourceKp)
            if (NameSourceKp == 'const') then
               call read_var('KP',kpConst)
            else if (index(NameSourceKp, 'file')>0) then
               cTempLines(1) = '#NGDC_INDICES'
               call read_var('kpFileName', kpFileName)
               cTempLines(2) = kpFileName
               cTempLines(3) = " "
               cTempLines(4) = "#END"

               call IO_set_Inputs(cTempLines)
               call read_NGDC_Indices(iError)

               if (iError /= 0) call CON_stop( &
                    NameSub//"Read indices FAILED (NGDC KP File)")
            else
               call CON_stop(NameSub//' Unrecognized SourceKp='//NameSourceKp)
            endif

         case("#NAME")
            call read_var('Name', Name)

         case("#SHUE")
            call read_var('UseShue', UseShue)

         case("#OUTPUT")
            call read_var('WriteStatic',WriteStatic)
            call read_var('WriteDynamic',WriteDynamic)
            call read_var('OutputInterval',tWriteOutput)
            call read_var('OutputType', OutputType)
            call read_var('MagneticType', MagneticType)

         case("#MLTSLICE")
            DoMltSlice=.true.
            call read_var('nMltSlice', nMltSlice)
            call read_var('DtMltSlice', DtMltSlice)

         case("#LOG")
            call read_var('WriteLogFile', WriteLogFile)

         case("#FILLING")
            call read_var('EmptyPeriodClosed', EmptyPeriodClosed)
            call read_var('EmptyPeriodOpen', EmptyPeriodOpen)
            call read_var('FillRate', FillDays) 
            call read_var('FluxMax', FluxMax)

         case("#TESTS")
            call read_var('TestFill', TestFill)

         case("#GMCOUPLING")
            call read_var('iGmFluidCouple', iGmFluidCouple)
            call read_var('TempPlasma',     TempPlas)
            
         case default
            if(iProc==0) then
               write(*,'(a,i4,a)')NameSub//' PS_ERROR at line ',i_line_read(),&
                    ' invalid command '//trim(NameCommand)
               if(UseStrict)call CON_stop('Correct PARAM.in!')
            end if
         end select
      end do

      ithermfirst=1		! So we do the setup routines in THERMAL

      LAMGAM=2.       ! Empirical E-field shielding parameter

    end subroutine read_param

  end subroutine PS_set_param

  !============================================================================
  subroutine PS_set_grid

    ! Set the grid descriptor for PS
    ! Since PS has a static grid the descriptor has to be set once.
    ! There can be many couplers that attempt to set the descriptor,
    ! so we must check IsInitialized.

    use ModProcPS
    use ModSizeDGCPM
    use ModMainDGCPM
    use CON_coupler

    real    :: zTmp(1)

    character(len=*), parameter :: NameSub='PS_set_grid'
    logical :: DoTest, DoTestMe

    !------------------------------------------------------
    call CON_set_do_test(NameSub,DoTest, DoTestMe)
    if(DoTest)write(*,*)NameSub,' IsInitialized=',IsInitialized
    if(IsInitialized) return
    IsInitialized=.true.

    zTmp = 0.0

    if (debug > 0) write(*,*) "begin PS_set_grid"

    ! DGCPM is a cylindrical model that operates in the equatorial plane.
    ! vrcells is the radial coordinate, vphicells the phi coordinate.
    call set_grid_descriptor(                &
         PS_,                                &! component index
         nDim=2,                             &! dimensionality
         nRootBlock_D=(/1,1/),               &! radius and MLT
         nCell_D =(/nthetacells,nphicells/), &! size of node based grid
         XyzMin_D=(/vrcells(1), 0.0/),       &! min radius and longitude indexes
         XyzMax_D=(/vrcells(nthetacells),    &
                   ctwopi/),                 &! max radius and longitude indexes
         TypeCoord='SMG',                    &! solar magnetic coord.
         Coord1_I=vrcells,                   &! radius
         Coord2_I=vphicells*ctwopi/360.,     &! longitudes in rads
         Coord3_I=zTmp)

    if(DoTestMe)then
       write(*,*) 'PS: DGCPM Grid info:'
       write(*,*) 'nTheta, nPhi cells = ', nthetacells,nphicells
       write(*,*) 'Radial grid range (RE) = ', vrcells(1), vrcells(nthetacells)
       write(*,*) 'Azimuthal grid range (deg) = ', &
            vphicells(1), vphicells(nphicells)
       write(*,*) 'Azimuthal grid range (rad) = ', &
            vphicells(1)*ctwopi/360., vphicells(nphicells)*ctwopi/360.
    end if
    
    if (debug > 0) write(*,*) "end PS_set_grid"

  end subroutine PS_set_grid

  !============================================================================
  subroutine PS_get_for_ie(nPoint,iPointStart,Index,Weight,Buff_V,nVar)

    ! Provide current for IE
    ! The value should be interpolated from nPoints with
    ! indexes stored in Index and weights stored in Weight
    ! The variables should be put into Buff_V(??)

    use CON_router,   ONLY: IndexPtrType, WeightPtrType
    use ModIonoDGCPM, ONLY: IONO_NORTH_RCM_JR, IONO_SOUTH_RCM_JR, &
         IONO_nTheta, IONO_nPsi

    character(len=*), parameter :: NameSub='PS_get_for_ie'

    integer,intent(in)            :: nPoint, iPointStart, nVar
    real,intent(out)              :: Buff_V(nVar)
    type(IndexPtrType),intent(in) :: Index
    type(WeightPtrType),intent(in):: Weight

    integer :: iLat, iLon, iBlock, iPoint
    real    :: w

    !--------------------------------------------------------------------------
    Buff_V = 0.0

    do iPoint = iPointStart, iPointStart + nPoint - 1

       iLat   = Index % iCB_II(1,iPoint)
       iLon   = Index % iCB_II(2,iPoint)
       iBlock = Index % iCB_II(3,iPoint)
       w      = Weight % Weight_I(iPoint)

       if(iBlock/=1)then
          write(*,*)NameSub,': iPoint,Index % iCB_II=',&
               iPoint,Index%iCB_II(:,iPoint)
          call CON_stop(NameSub//&
               ' SWMF_ERROR iBlock should be 1=North in PS-IE coupling')
       end if

       if(iLat<1 .or. iLat>IONO_nTheta*2 .or. iLon<1 .or. iLon>IONO_nPsi+1)then
          write(*,*)'iLat,iLon=',iLat, IONO_nTheta*2, iLon, IONO_nPsi
          call CON_stop(NameSub//' SWMF_ERROR index out of range')
       end if

       ! Only worry about the northern hemisphere....  
       ! IE can fix the southern hemisphere.
       if (iLat <= IONO_nTheta .and. iLon <= IONO_nPsi) &
            Buff_V(1) = Buff_V(1) + w * IONO_NORTH_RCM_JR(iLat,iLon)

       if (iLat > IONO_nTheta .and. iLon <= IONO_nPsi) &
            Buff_V(1) = Buff_V(1) + &
            w * IONO_SOUTH_RCM_JR(2*IONO_nTheta-iLat+1,iLon)

    end do

  end subroutine PS_get_for_ie

  !============================================================================
  subroutine PS_put_from_ie(nThetaIn, nPhiIn, BufferIn_II)

    use ModNumConst, ONLY: cRadToDeg
    use ModIoUnit,   ONLY: UnitTmp_
    use CON_coupler, ONLY: Grid_C, IE_
    !use ModMainDGCPM
    use ModCoupleDGCPM

    integer, intent(in):: nThetaIn, nPhiIn
    real,    intent(in):: BufferIn_II(nThetaIn, nPhiIn)

    integer, save :: jShift
    logical, save :: IsInitialized=.false.

    real    :: IeLong_I(nPhiIn)
    integer :: i, j, nIeGhost=0
    
    logical :: DoTest, DoTestMe
    character(len=*), parameter:: NameSub = 'PS_put_from_ie'
    !-------------------------------------------------------------------------
    call CON_set_do_test(NameSub,DoTest,DoTestMe)
    
    ! Check for initialization.
    if(.not. IsInitialized)then
       if(DoTestMe) write(*,*)NameSub//': Intializing coupling...'

       ! Determine number of IE ghost cells in longitude.
       ! We do not want to have extra points.
       IeLong_I = Grid_C(IE_)%Coord2_I*cRadToDeg ! copy for convenience.
       do j=1, nPhiIn
          ! Ghost cells have same longitude, +360:
          if(IeLong_I(j)+360./=IeLong_I(nPhiIn+1-j)) exit
       end do
       nIeGhost=j-1
       
       if(DoTestMe)write(*,*)NameSub//': Number of IE ghost cells: ', nIeGhost
       
       ! Get IE grid size:
       nThetaIe  = nThetaIn
       nPhiIe    = nPhiIn-nIeGhost+2 !!! Make our longitude have 2 ghost cells.
       
       ! Allocate variables:
       allocate(IePot_II(nThetaIe, nPhiIe))
       allocate(IeTheta_I(nThetaIe), IePhi_I(nPhiIe))

       ! Get IE grid from coupling info.
       IeTheta_I           = Grid_C(IE_)%Coord1_I*cRadToDeg
       IePhi_I(2:nPhiIe-1) = Grid_C(IE_)%Coord2_I(:nPhiIn-nIeGhost)*cRadToDeg

       ! Get index for rotation:
       do j=1, nPhiIn-j
          if(IePhi_I(j+1)>180.)exit
       end do
       jShift=j
       if(DoTestMe)write(*,*)NameSub//': jShift = ', jshift
       
       ! Wrap first and last longitudes to create ghost cells.
       ! This will enforce continuity during interpolation.
       IePhi_I(1)      = IePhi_I(nPhiIe-1) -360.0
       iePhi_I(nPhiIe) = IePhi_I(2)        +360.0
       
       ! Set initialization state:
       IsInitialized = .true.

       ! Write debug info:
       if(DoTestMe)then
          write(*,*)NameSub//': IE Grid Info:'
          write(*,*)'  Theta size, min, max = ', &
               nThetaIn, IeTheta_I(1),IeTheta_I(nThetaIn)
          write(*,*)'  Phi size, min, max = ', &
               nPhiIn, IePhi_I(1), IePhi_I(nPhiIn)
       end if
    end if

    ! Transfer potential to module-level variables.
    ! Rotate 180 degrees without filling ghost cells.
    IePot_II(:,     2:nPhiIe-jShift-1)=BufferIn_II(:,jShift+1:nPhiIn-nIeGhost)
    IePot_II(:,nPhiIe-jShift:nPhiIe-1)=BufferIn_II(:,        :jShift)

    ! Wrap values in longitude to ensure continuity:
    IePot_II(:, 1)      = IePot_II(:,nPhiIe-1)
    IePot_II(:, nPhiIe) = IePot_II(:,2)

    if(DoTestMe)then
       ! Print CPCP to screen:
       write(*,*) "PS: received potential from IE!!"
       write(*,'(a,f11.1,a,f11.1,a,f11.1,a)') "PS CPCP == ", &
            maxval(IePot_II), ' - ', minval(IePot_II), ' = ', &
            maxval(IePot_II) - minval(IePot_II), 'V'
       write(*,*) "PS: Size of pot array = ", size(BufferIn_II), &
            size(BufferIn_II,1), size(BufferIn_II,2)
       ! Write potential to file:
       open(unit=UnitTmp_, file='ps_potential.txt', status='replace')
       write(UnitTmp_,*)'Colat   Lon   Potential(V)'
       do i=1, nThetaIe
          do j=2, nPhiIe-1
             write(UnitTmp_, '(f6.2, 1x, f6.2, 1x, f9.1)') &
                  IeTheta_I(i), IePhi_I(j), IePot_II(i,j)
          end do
       end do
       close(UnitTmp_)
    end if
    
    isCoupled = .true.

    RETURN

  end subroutine PS_put_from_ie

  !============================================================================
  subroutine PS_put_from_ie_complete
    
    !--------------------------------------------------------------------------

    ! Currently Empty.
    return

  end subroutine PS_put_from_ie_complete

  !============================================================================
  subroutine PS_get_for_gm(Buffer_IIV,iSizeIn,jSizeIn,nVar,NameVarIn)

    ! Obtain total number density as a function of lat/lon.
    ! Rather than put density/pressure into a "hard coded" slot,
    ! allow user to select iGmCoupleFluid using #GMCOUPLING in #PS portion.
    ! NameVarIn is parsed, fluid corresponding to iGmCoupleFluid is used.
    ! Default action: assume single fluid and place information there.
    ! Pressure is set by assuming constant temperature selected by user.

    use ModConst,       ONLY: cBoltzmann, cEVToK, cProtonMass
    use ModMainDGCPM,   ONLY: mgridden
    use ModCoupleDGCPM, ONLY: iGmFluidCouple, TempPlas
    
    integer, intent(in)                               :: iSizeIn,jSizeIn,nVar
    real, dimension(iSizeIn,jSizeIn,nVar), intent(out):: Buffer_IIV
    character (len=*),intent(in)                      :: NameVarIn

    ! Local variables:
    integer :: i, iEnd, nGmFluids, iPress=1, iRho=2

    character(len=20)  :: NameVar_I(nVar)
    character(len=100) :: NameVarRemain, NameVarNow
    
    ! Testing variables:
    character (len=*),parameter :: NameSub='PS_get_for_gm'
    logical                     :: DoTest, DoTestMe
    
    !--------------------------------------------------------------------------
    call CON_set_do_test(NameSub,DoTest,DoTestMe)

    if (DoTestMe) &
         write(*,*)NameSub,' starting with iSizeIn,jSizeIn,nVar,NameVar=',&
         iSizeIn,jSizeIn,nVar,NameVarIn
    
    ! Initialize all density and pressures to -1 (i.e., no coupling)
    Buffer_IIV=-1.0

    ! Rather than assume that a set variable list is sent to PS corresponding
    ! to either single or two-fluid MHD, parse the variable list appropriately.
    ! Parse the names of the variables requested by GM:
    NameVarRemain = NameVarIn
    if(DoTestMe)write(*,*)' PS: Initially, NameVarRemain = ', NameVarRemain
    do i=1,nVar
       ! Find length of current variable name.
       ! Go to end of string if delimiter not found.
       iEnd = index(NameVarRemain,':')
       if(iEnd==0) iEnd=len_trim(NameVarRemain)+1

       ! Extract the current variable name:
       NameVar_I(i) = NameVarRemain(:iEnd-1)

       ! Save only remaining variables, blank out old names:
       NameVarRemain = NameVarRemain(iEnd+1:)//'                         '
       if(DoTestMe) then
          write(*,*)NameSub//': Found variable = ', NameVar_I(i)
          write(*,*)NameSub//': NameVarRemain = ', NameVarRemain
       end if
       
       ! Ensure that all variables are "rho" or "p" variables.
       ! If not, then there's something wrong with the coupling.
       NameVarNow = NameVar_I(i)
       iEnd = len_trim(NameVarNow)

       if( ( index(NameVarNow(iEnd:iEnd),'p')<1 ) .and. &
           ( index(NameVarNow,'rho')<1) ) &
            call CON_stop(NameSub// &
            ': NameVar includes variables outside of p and rho')
    end do

    ! Calculate number of fluids:
    nGmFluids = nVar/2 - 1

    ! Set indexes for fluid to which we couple:
    if(iGmFluidCouple>0)then
       iPress = 2+iGmFluidCouple
       iRho   = 2+nGmFluids+iGmFluidCouple
    end if
    
    if(DoTestMe)then
       write(*,*)NameSub//' fluid coupling info:'
       write(*,*)'   PS found ', nGmFluids, ' fluids in NameVar.'
       write(*,*)'   Coupling to fluid #', iGmFluidCouple
       write(*,*)'   NameVar = ', NameVarIn
       write(*,*)'   Writing density  to iVar, Var = ',iRho, NameVar_I(iRho)
       write(*,*)'   Writing pressure to iVar, Var = ',iPress, NameVar_I(iPress)
    end if

    ! Now, set values in SI units to pass back to GM.
    ! GM will only couple if TOTAL fluid values are >0.
    ! Even in MF coupling, set both total AND individual fluid values.
    ! Total fluid coupling:
    Buffer_IIV(:,:,2) = mgridden * cProtonMass! kg/m^3
    Buffer_IIV(:,:,1) = tempPlas*cEVToK*cBoltzmann*mgridden ! P=nkT in Pa
    ! Multi fluid coupling:
    if(nGmFluids>0)then
       Buffer_IIV(:,:,iRho)   = mgridden * cProtonMass
       Buffer_IIV(:,:,iPress) = tempPlas*cEVToK*cBoltzmann*mgridden
    end if

    if(DoTestMe)then
       write(*,*)NameSub//': Max/Min values sent from PS to GM:'
       write(*,'(a,2e12.3)')'   Density [cm-3] = ', &
            maxval(mgridden/1E6), minval(mgridden/1E6)
       write(*,'(a,2e12.3)')'   Pressure [Pa]  = ', &
            maxval(Buffer_IIV(:,:,iPress)), minval(Buffer_IIV(:,:,iPress))
    end if
    
  end subroutine PS_get_for_gm
  
  !============================================================================

  subroutine PS_init_session(iSession, tSimulation)

    ! Initialize the Plasmasphere (PS) module for session iSession

    use CON_physics,    ONLY: get_time, get_planet, get_axes
    use CON_time,       ONLY: tSimulationMax
    use ModTimeConvert, ONLY: TimeType, time_real_to_int
    use ModCoupleDGCPM
    use ModIoDGCPM
    use ModMainDGCPM
    use ModTimeDGCPM

    !INPUT PARAMETERS:
    integer, intent(in) :: iSession      ! session number (starting from 1)
    real,    intent(in) :: tSimulation   ! seconds from start time

    !DESCRIPTION:
    ! Initialize the Plasmasphere (PS) module for session iSession

    ! Debug variables:
    character(len=*), parameter :: NameSub='PS_init_session'
    logical                     :: DoTest,DoTestMe
    type(TimeType)              :: TimeNow

    !--------------------------------------------------------------------------
    call CON_set_do_test(NameSub,DoTest,DoTestMe)

    ! Use the SWMF time max, set max number of steps.
    NSTEP=NINT(tSimulationMax/DT/2.)
    
    ! Set up internal time variables
    time = tSimulation
    t=time
    nst=nint(time/dt/2.) + 1
    nkp=nint(10800./dt/2.)

    ! Synchronize time with SWMF:
    call get_time(tCurrentOut=CurrentTime, tStartOut=StartTime)

    ! Print timing
    if(DoTestMe)then
       write(*,*) 'PS: DGCPM initial timing values:'
       write(*,'(a,3(i10))')' PS: Timing indices nStep, nSt, nKp =',nStep,nSt,nKp
       write(*,'(a,f8.1)') ' PS: Time step dT = ', dt
       TimeNow%Time=StartTime
       call time_real_to_int(TimeNow)
       write(*,'(a4, a15,i4.4,i2.2,i2.2,"-",i2.2,i2.2,i2.2,"-",i3.3)') &
            'PS:', 'Start Time: ', &
            TimeNow%iYear, TimeNow%iMonth, TimeNow%iDay, &
            TimeNow%iHour, TimeNow%iMinute, TimeNow%iSecond, &
            floor(TimeNow%FracSecond*1000.0)
       
       TimeNow%Time=CurrentTime
       call time_real_to_int(TimeNow)
       write(*,'(a4, a15,i4.4,i2.2,i2.2,"-",i2.2,i2.2,i2.2,"-",i3.3)') &
            'PS:', 'Current Time: ', &
            TimeNow%iYear, TimeNow%iMonth, TimeNow%iDay, &
            TimeNow%iHour, TimeNow%iMinute, TimeNow%iSecond, &
            floor(TimeNow%FracSecond*1000.0)
    end if
    
    ! Set Kp values:
    call GetKPA()

    ! Load restart file, initialize grid/domain, etc.:
    call thermal()

    ! Initialize electric field values:
    if (IsCoupled) then
       call setpot(IeTheta_I, nThetaIe, IePhi_I, nPhiIe, IePot_II)
    else
       call magconv
       call setpot(vthetacells,nthetacells,vphicells,nphicells,mgridpot)
    endif
     
    if (TestFill.gt.0) call TestFilling(1.0)
    
    ! Write/initialize output as necessary:
    call write_dgcpm_output(nStep, CurrentTime)
    
    ! Finish Initialization     
    WriteStatic = .true.

    if (DoTestMe) write(*,*) "PS: Initialization Complete."

  end subroutine PS_init_session

  !============================================================================

  subroutine PS_finalize(tSimulation)

    use ModProcPS
    use CON_physics, ONLY: get_time
    use ModIoDGCPM,  ONLY: iUnitSlice, DoMltSlice, iUnitMlt, nMltSlice
    use ModCoupleDGCPM

    !INPUT PARAMETERS:
    real,     intent(in) :: tSimulation   ! seconds from start time

    ! Other variables:
    integer :: i

    character(len=*), parameter :: NameSub='PS_finalize'

    !--------------------------------------------------------------------------

    call wresult()

    ! Close files:
    close(iUnitSlice)
    if(DoMltSlice) then
       do i=1, nMltSlice
          close(iUnitMlt(i))
       end do
       deallocate(iUnitMlt)
    end if

    ! Deallocate coupling variables.
    if(allocated(IePot_II))  deallocate(IePot_II)
    if(allocated(IeTheta_I)) deallocate(IeTheta_I)
    if(allocated(IePhi_I))   deallocate(IePhi_I)

  end subroutine PS_finalize

  !============================================================================

  subroutine PS_save_restart(tSimulation)

    use ModIoUnit,   ONLY: UNITTMP_
    use ModIoDGCPM,  ONLY: cRestartOut
    use ModMainDGCPM

    !INPUT PARAMETERS:
    real,     intent(in) :: tSimulation   ! seconds from start time

    character(len=*), parameter :: NameSub='PS_save_restart'
    !--------------------------------------------------------------------------

    open(unit=UnitTMP_, form = 'formatted', &
         file=cRestartOut//'dgcpm_restart.dat')     
    write(UnitTMP_,*) nthetacells, nphicells
    write(UnitTMP_,*) vthetacells
    write(UnitTMP_,*) vphicells
    write(UnitTMP_,*) mgridden
    write(UnitTMP_,*) mgridx
    write(UnitTMP_,*) mgridy
    write(UnitTMP_,*) mgridoc
    write(UnitTMP_,*) mgridpot
    write(UnitTMP_,*) mgridvr
    write(UnitTMP_,*) mgridvp
    write(UnitTMP_,*) mgridn
    write(UnitTMP_,*) mgridvol
    
    close(unit = UnitTMP_)

  end subroutine PS_save_restart

  !============================================================================

  subroutine PS_run(tSimulation,tSimulationLimit)

    use ModProcPS
    use ModMainDGCPM
    use ModIoDGCPM
    use CON_physics, ONLY: get_time, get_axes, time_real_to_int
    use ModKind
    use ModTimeDGCPM
    use ModCoupleDGCPM

    !INPUT/OUTPUT ARGUMENTS:
    real, intent(inout) :: tSimulation   ! current time of component

    !INPUT ARGUMENTS:
    real, intent(in) :: tSimulationLimit ! simulation time not to be exceeded

    real(Real8_) :: tStart
    real         :: dt_requested

    character(len=*), parameter :: NameSub='PS_run'

    logical :: DoTest,DoTestMe
    !--------------------------------------------------------------------------

    call CON_set_do_test(NameSub,DoTest,DoTestMe)

    if(DoTest)write(*,*)NameSub,': iProc,tSimulation,tSimulationLimit=',&
         iProc,tSimulation,tSimulationLimit

    !  if (debug .gt. 0) write(*,*) "PS_run"

    dt_requested = tsimulationlimit-tsimulation
    if (dt_requested < dt*2) dt = dt_requested/2

    CurrentTime = StartTime + tSimulation


    t = tSimulation

    nst=nint(t/dt/2.) + 1
    nkp=nint(10800./dt/2.)

    ! Get Kp value:
    call getkpa()

    !  if (debug .gt. 0) write(*,*) "magconv"
    if (.not.(isCoupled)) call magconv()
    
    !  if (debug .gt. 0) write(*,*) "thermal"
    call thermal

    ! Update timing.
    tSimulation = tSimulation+2.*dt
    CurrentTime = StartTime + tSimulation

    ! Write output files:
    call write_dgcpm_output(int(tSimulation/(2.0*dt)), CurrentTime)
    
  end subroutine PS_run

  !============================================================================

  !subroutine PS_put_from_ie(Buffer_IIV, iSize, jSize, nVar)

  !  character (len=*),parameter :: NameSub='PS_put_from_ie'

  !  integer, intent(in)           :: iSize, jSize, nVar
  !  real, intent(out)             :: Buffer_IIV(iSize,jSize,nVar)

  !NOTE: The Buffer variables have been pushed to all PS processors already.

  !  write(*,*) NameSub,' -- called but not yet implemented.'

  !end subroutine PS_put_from_ie

end module PS_wrapper
