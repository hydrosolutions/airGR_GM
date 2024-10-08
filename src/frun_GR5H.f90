!------------------------------------------------------------------------------
!    Subroutines relative to the annual GR5H model
!------------------------------------------------------------------------------
! TITLE   : airGR
! PROJECT : airGR
! FILE    : frun_GR5H.f
!------------------------------------------------------------------------------
! AUTHORS
! Original code: Le Moine, N., Ficchì, A.
! Cleaning and formatting for airGR: Coron, L.
! Further cleaning: Thirel, G.
!------------------------------------------------------------------------------
! Creation date: 2006
! Last modified: 26/11/2019
!------------------------------------------------------------------------------
! REFERENCES
! Ficchi, A. (2017). An adaptive hydrological model for multiple time-steps:
! Diagnostics and improvements based on fluxes consistency. PhD thesis,
! UPMC - Irstea Antony, Paris, France.
!
! Ficchi, A., Perrin, C. and Andréassian, V. (2019). Hydrological modelling at
! multiple sub-daily time steps: model improvement via flux-matching. Journal
! of Hydrology, 575, 1308-1327, doi: 10.1016/j.jhydrol.2019.05.084.
!------------------------------------------------------------------------------
! Quick description of public procedures:
!         1. frun_gr5h
!         2. MOD_GR5H
!------------------------------------------------------------------------------


      SUBROUTINE frun_gr5h(LInputs,InputsPrecip,InputsPE,NParam,Param, &
                           NStates,StateStart,Imax,NOutputs,IndOutputs, &
                           Outputs,StateEnd)
! Subroutine that initializes GR5H, get its parameters, performs the call
! to the MOD_GR5H subroutine at each time step, and stores the final states
! Inputs
!       LInputs      ! Integer, length of input and output series
!       InputsPrecip ! Vector of real, input series of total precipitation [mm/hour]
!       InputsPE     ! Vector of real, input series of potential evapotranspiration (PE) [mm/hour]
!       NParam       ! Integer, number of model parameters
!       Param        ! Vector of real, parameter set
!       NStates      ! Integer, number of state variables
!       StateStart   ! Vector of real, state variables used when the model run starts (store levels [mm] and Unit Hydrograph (UH) storages [mm])
!       Imax         ! Real, fixed capacity of the interception store [mm] (used only if IsIntStore >= 0)
!       NOutputs     ! Integer, number of output series
!       IndOutputs   ! Vector of integer, indices of output series
! Outputs
!       Outputs      ! Vector of real, output series
!       StateEnd     ! Vector of real, state variables at the end of the model run (store levels [mm] and Unit Hydrograph (UH) storages [mm])


      


      Implicit None

      !! dummies
      ! in
      integer, intent(in) :: LInputs,NParam,NStates,NOutputs
      doubleprecision, dimension(LInputs), intent(in) :: InputsPrecip
      doubleprecision, dimension(LInputs), intent(in) :: InputsPE
      doubleprecision, dimension(NParam),  intent(in) :: Param
      doubleprecision, dimension(NStates), intent(in) :: StateStart
      doubleprecision, intent(in) :: Imax ! interception capacity (fixed parameter) used only if IsIntStore >= 0
      integer, dimension(NOutputs),        intent(in) :: IndOutputs
      ! out
      doubleprecision, dimension(NStates), intent(out) :: StateEnd
      doubleprecision, dimension(LInputs,NOutputs), intent(out) :: Outputs

      !! locals
      logical :: IsIntStore         ! TRUE if interception store is used, FALSE otherwise
      integer :: I,K
      integer, parameter :: NH=480,NMISC=30
      doubleprecision, dimension(3)     :: St
      doubleprecision, dimension(2*NH)  :: StUH2, OrdUH2
      doubleprecision, dimension(NMISC) :: MISC
      doubleprecision :: D,P1,E,Q

      IF (Imax .LT. 0.d0) THEN
        IsIntStore = .FALSE.
      ELSE
        IsIntStore = .TRUE.
      ENDIF

      !--------------------------------------------------------------
      ! Initializations
      !--------------------------------------------------------------

      ! initialization of model states to zero
      St=0.
      StUH2=0.

      ! initialization of model states using StateStart
      St(1) = StateStart(1)
      St(2) = StateStart(2)
      IF (IsIntStore .EQV. .TRUE.) St(3) = StateStart(4)

      DO I=1,2*NH
        StUH2(I)=StateStart(7+NH+I)
      ENDDO

      ! parameter values
      ! Param(1) : production store capacity (X1 - PROD) [mm]
      ! Param(2) : intercatchment exchange coefficient (X2 - CES1) [mm/h]
      ! Param(3) : routing store capacity (X3 - ROUT) [mm]
      ! Param(4) : time constant of unit hydrograph (X4 - TB) [hour]
      ! Param(5) : intercatchment exchange threshold (X5 - CES2) [-]

      !computation of HU ordinates
      OrdUH2 = 0.

      D=1.25
      CALL UH2_H(OrdUH2,Param(4),D)

      ! initialization of model outputs
      Q = -999.999
      MISC = -999.999
!      StateEnd = -999.999 !initialization made in R
!      Outputs = -999.999  !initialization made in R



      !--------------------------------------------------------------
      ! Time loop
      !--------------------------------------------------------------
      DO k=1,LInputs
        P1=InputsPrecip(k)
        E =InputsPE(k)
!        Q = -999.999
!        MISC = -999.999
        ! model run on one time step
        CALL MOD_GR5H(St,StUH2,OrdUH2,Param,IsIntStore,Imax,P1,E,Q,MISC)
        ! storage of outputs
        DO I=1,NOutputs
          Outputs(k,I)=MISC(IndOutputs(I))
        ENDDO
      ENDDO
      ! model states at the end of the run
      StateEnd(1) = St(1)
      StateEnd(2) = St(2)
      StateEnd(4) = St(3)
      DO K=1,2*NH
        StateEnd(7+NH+K)=StUH2(K)
      ENDDO

      RETURN

      ENDSUBROUTINE





!################################################################################################################################




!**********************************************************************
      SUBROUTINE MOD_GR5H(St,StUH2,OrdUH2,Param,IsIntStore,Imax,P1,E,Q,MISC)
! Calculation of streamflow on a single time step (hour) with the GR5H model
! Inputs:
!       St     Vector of real, model states in stores at the beginning of the time step [mm]
!       StUH2  Vector of real, model states in Unit Hydrograph 2 at the beginning of the time step [mm/h]
!       OrdUH2 Vector of real, ordinates in UH2 [-]
!       Param  Vector of real, model parameters [various units]
!       IsIntStore  Logical, whether interception store is used
!       Imax   Real, value of interception store capacity, fixed parameter [mm]
!       P1     Real, value of rainfall during the time step [mm/h]
!       E      Real, value of potential evapotranspiration during the time step [mm/h]
! Outputs:
!       St     Vector of real, model states in stores at the end of the time step [mm/h]
!       StUH2  Vector of real, model states in Unit Hydrograph 2 at the end of the time step [mm/h]
!       Q      Real, value of simulated flow at the catchment outlet for the time step [mm/h]
!       MISC   Vector of real, model outputs for the time step [mm or mm/h]
!**********************************************************************
      Implicit None

      !! locals
      integer, parameter :: NParam=5,NMISC=30,NH=480
      doubleprecision :: A,EN,ES,PN,PR,PS,WS,EI
      doubleprecision :: PERC,EXCH,QR,QD,Q1,Q9
      doubleprecision :: AE,AEXCH1,AEXCH2
      integer :: K
      doubleprecision, parameter :: B=0.9
      doubleprecision, parameter :: stored_val=759.69140625
      doubleprecision :: expWS, TWS, Sr, Rr ! speed-up

      !! dummies
      ! in
      doubleprecision, dimension(NParam), intent(in)  :: Param
      logical, intent(in) :: IsIntStore
      doubleprecision, intent(in) :: P1,E,Imax
      doubleprecision, dimension(2*NH), intent(inout) :: OrdUH2
      ! inout
      doubleprecision, dimension(3), intent(inout)    :: St
      doubleprecision, dimension(2*NH), intent(inout) :: StUH2
      ! out
      doubleprecision, intent(out) :: Q
      doubleprecision, dimension(NMISC), intent(out)  :: MISC

      A=Param(1)


! Interception and production store
      IF (IsIntStore .EQV. .TRUE.) THEN

      ! MODIFIED - A. Ficchi
      ! Calculation of interception fluxes [EI] and throughfall [PTH]
      ! & update of the Interception store state, St(3)

      ! Interception store calculation, with evaporation prior to throughfall
        EI=MIN(E, P1+St(3))
        PN=MAX(0.d0, P1-(Imax-St(3))-EI)
        St(3)=St(3)+P1-EI-PN
        EN=MAX(0.d0, E-EI)

        ! Production (SMA) store, saving the total actual evaporation including evaporation from interception store (EI)
        IF(EN.GT.0) THEN
          WS=EN/A
          IF(WS.GT.13)WS=13.
          expWS=exp(2.*WS)
          TWS = (expWS - 1.)/(expWS + 1.)
          Sr = St(1)/A
          ES=St(1)*(2.-Sr)*TWS/(1.+(1.-Sr)*TWS)
          St(1)=St(1)-ES
          AE=ES+EI
        ELSE
          AE=EI
          ES = 0.
        ENDIF

        IF(PN.GT.0.) THEN
          WS=PN/A
          IF(WS.GT.13) WS=13.
          expWS=exp(2.*WS)
          TWS = (expWS - 1.)/(expWS + 1.)
          Sr = St(1)/A
          PS=A*(1.-Sr*Sr)*TWS/(1.+Sr*TWS)
          PR=PN-PS
          St(1)=St(1)+PS
        ELSE
          PS=0.
          PR=0.
        ENDIF
      ENDIF


      IF (IsIntStore .EQV. .FALSE.) THEN
        IF(P1.LE.E) THEN
          EN=E-P1
          PN=0.
          WS=EN/A
          IF(WS.GT.13.) WS=13.
          ! speed-up
          expWS=exp(2.*WS)
          TWS = (expWS - 1.)/(expWS + 1.)
          Sr = St(1)/A
          ES=St(1)*(2.-Sr)*TWS/(1.+(1.-Sr)*TWS)
          ! ES=X(2)*(2.-X(2)/A)*tanHyp(WS)/(1.+(1.-X(2)/A)*tanHyp(WS))
          ! end speed-up
          AE=ES+P1
          EI = P1
          St(1)=St(1)-ES
          PS=0.
          PR=0.
        ELSE
          EN=0.
          ES=0.
          AE=E
          EI = E
          PN=P1-E
          WS=PN/A
          IF(WS.GT.13.) WS=13.
          ! speed-up
          expWS=exp(2.*WS)
          TWS = (expWS - 1.)/(expWS + 1.)
          Sr = St(1)/A
          PS=A*(1.-Sr*Sr)*TWS/(1.+Sr*TWS)
          ! PS=A*(1.-(X(2)/A)**2.)*tanHyp(WS)/(1.+X(2)/A*tanHyp(WS))
          ! end speed-up

          PR=PN-PS
          St(1)=St(1)+PS
        ENDIF
      ENDIF

! Percolation from production store
      IF(St(1).LT.0.) St(1)=0.

      ! speed-up
      ! (21/4)**4 = 759.69140625 = stored_val
      Sr = St(1)/Param(1)
      Sr = Sr * Sr
      Sr = Sr * Sr
      PERC=St(1)*(1.-1./SQRT(SQRT(1.+Sr/stored_val)))
      ! PERC=X(2)*(1.-(1.+(X(2)/(21./4.*Param(1)))**4.)**(-0.25))
      ! end speed-up

      St(1)=St(1)-PERC

      PR=PR+PERC

! Convolution of unit hydrograph UH2
      DO K=1,MAX(1,MIN(2*NH-1,2*INT(Param(4)+1.)))
        StUH2(K)=StUH2(K+1)+OrdUH2(K)*PR
      ENDDO
      StUH2(2*NH)=OrdUH2(2*NH)*PR

! Split of unit hydrograph first component into the two routing components
      Q9=StUH2(1)*B
      Q1=StUH2(1)*(1.-B)

! Potential intercatchment semi-exchange
      EXCH=Param(2)*(St(2)/Param(3)-Param(5))

! Routing store
      AEXCH1=EXCH
      IF((St(2)+Q9+EXCH).LT.0.) AEXCH1=-St(2)-Q9
      St(2)=St(2)+Q9+EXCH
      IF(St(2).LT.0.) St(2)=0.

      ! speed-up
      Rr = St(2)/Param(3)
      Rr = Rr * Rr
      Rr = Rr * Rr
      QR = St(2)*(1.-1./SQRT(SQRT(1.+Rr)))
      ! QR=X(1)*(1.-(1.+(X(1)/Param(3))**4.)**(-1./4.))
      ! end speed-up

      St(2)=St(2)-QR

! Runoff from direct branch QD
      AEXCH2=EXCH
      IF((Q1+EXCH).LT.0.) AEXCH2=-Q1
      QD=MAX(0.d0,Q1+EXCH)

! Total runoff
      Q=QR+QD
      IF(Q.LT.0.) Q=0.

! Variables storage
      MISC( 1)=E             ! PE     ! [numeric] observed potential evapotranspiration [mm/h]
      MISC( 2)=P1            ! Precip ! [numeric] observed total precipitation [mm/h]
      MISC( 3)=St(3)         ! Interc ! [numeric] interception store level (St(3)) [mm]
      MISC( 4)=St(1)         ! Prod   ! [numeric] production store level (St(1)) [mm]
      MISC( 5)=PN            ! Pn     ! [numeric] net rainfall [mm/h]
      MISC( 6)=PS            ! Ps     ! [numeric] part of Ps filling the production store [mm/h]
      MISC( 7)=AE            ! AE     ! [numeric] actual evapotranspiration [mm/h]
      MISC( 8)=EI            ! EI     ! [numeric] evapotranspiration from rainfall neutralisation or interception store [mm/h]
      MISC( 9)=ES            ! ES     ! [numeric] evapotranspiration from production store [mm/h]
      MISC(10)=PERC          ! Perc   ! [numeric] percolation (PERC) [mm/h]
      MISC(11)=PR            ! PR     ! [numeric] PR=PN-PS+PERC [mm/h]
      MISC(12)=Q9            ! Q9     ! [numeric] outflow from UH1 (Q9) [mm/h]
      MISC(13)=Q1            ! Q1     ! [numeric] outflow from UH2 (Q1) [mm/h]
      MISC(14)=St(2)         ! Rout   ! [numeric] routing store level (St(2)) [mm]
      MISC(15)=EXCH          ! Exch   ! [numeric] potential semi-exchange between catchments (EXCH) [mm/h]
      MISC(16)=AEXCH1        ! AExch1 ! [numeric] actual exchange between catchments from branch 1 (AEXCH1) [mm/h]
      MISC(17)=AEXCH2        ! AExch2 ! [numeric] actual exchange between catchments from branch 2 (AEXCH2) [mm/h]
      MISC(18)=AEXCH1+AEXCH2 ! AExch  ! [numeric] actual total exchange between catchments (AEXCH1+AEXCH2) [mm/h]
      MISC(19)=QR            ! QR     ! [numeric] outflow from routing store (QR) [mm/h]
      MISC(20)=QD            ! QD     ! [numeric] outflow from UH2 branch after exchange (QD) [mm/h]
      MISC(21)=Q             ! Qsim   ! [numeric] simulated outflow at catchment outlet [mm/h]


      ENDSUBROUTINE


