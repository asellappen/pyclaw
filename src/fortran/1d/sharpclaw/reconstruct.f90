module reconstruct
    use weno

    double precision, allocatable  :: dq1m(:)
    double precision, allocatable, private :: uu(:,:),dq(:,:)
    double precision, allocatable, private :: uh(:,:,:),gg(:,:),hh(:,:),u(:,:,:)
    double precision, allocatable, private :: evl(:,:,:),evr(:,:,:)
    double precision, private  :: epweno = 1.e-36
    logical :: recon_alloc = .False.

contains

    subroutine alloc_recon_workspace(maxnx,mbc,meqn,mwaves,lim_type,char_decomp)
        integer,intent(in) :: maxnx,mbc,meqn,mwaves,char_decomp,lim_type

        select case(lim_type)
            case(1)
            select case(char_decomp)
                case(1) ! Storage for tvd2_wave()
                    allocate(uu(mwaves,1-mbc:maxnx+mbc))
                case(2) ! Storage for tvd2_char()
                    ! Do the array bounds here cause a bug?
                    allocate(dq(meqn,1-mbc:maxnx+mbc))
                    allocate( u(meqn,2,1-mbc:maxnx+mbc))
                    allocate(hh(-1:1,1-mbc:maxnx+mbc))
            end select
            case(2)
            select case(char_decomp)
                case(0)
                    allocate(uu(2,maxnx+2*mbc))
                    allocate( dq1m(maxnx+2*mbc))
                case(2) ! Storage for weno5_char
                    allocate(dq(meqn,maxnx+2*mbc))
                    allocate(uu(2,maxnx+2*mbc))
                    allocate(hh(-2:2,maxnx+2*mbc))
                case(3) ! Storage for weno5_trans
                    allocate(dq(meqn,maxnx+2*mbc))
                    allocate(gg(meqn,maxnx+2*mbc))
                    allocate( u(meqn,2,maxnx+2*mbc))
                    allocate(hh(-2:2,maxnx+2*mbc))
                    allocate(uh(meqn,2,maxnx+2*mbc))
            end select
        end select
        recon_alloc = .True.

    end subroutine alloc_recon_workspace


    subroutine dealloc_recon_workspace(lim_type,char_decomp)
        integer,intent(in) :: lim_type,char_decomp

        select case(lim_type)
            case(1)
            select case(char_decomp)
                case(1) ! Storage for tvd2_wave()
                    deallocate(uu)
                case(2) ! Storage for tvd2_char()
                    deallocate(dq)
                    deallocate( u)
                    deallocate(hh)
            end select
            case(2)
             select case(char_decomp)
                case(0)
                    deallocate(uu)
                    deallocate(dq1m)
                case(2) ! Storage for weno5_char
                    deallocate(dq)
                    deallocate(uu)
                    deallocate(hh)
                case(3) ! Storage for weno5_trans
                    deallocate(dq)
                    deallocate(gg)
                    deallocate( u)
                    deallocate(hh)
                    deallocate(uh)
            end select
            recon_alloc = .False.
        end select
    end subroutine dealloc_recon_workspace

    ! ! ===================================================================
    ! subroutine weno5(q,ql,qr,meqn,maxnx,mbc)
    ! ! ===================================================================

    !     implicit double precision (a-h,o-z)

    !     double precision, intent(in) :: q(meqn,maxnx+2*mbc)
    !     double precision, intent(out) :: ql(meqn,maxnx+2*mbc),qr(meqn,maxnx+2*mbc)

    !     integer :: meqn, mx2

    !     mx2  = size(q,2); meqn = size(q,1)

    !     !loop over all equations (all components).  
    !     !the reconstruction is performed component-wise;
    !     !no characteristic decomposition is used here

    !     do m=1,meqn

    !         forall (i=2:mx2)
    !             ! compute and store the differences of the cell averages
    !             dq1m(i)=q(m,i)-q(m,i-1)
    !         end forall

    !         ! the reconstruction

    !         do m1=1,2

    !             ! m1=1: construct ql
    !             ! m1=2: construct qr

    !             im=(-1)**(m1+1)
    !             ione=im; inone=-im; intwo=-2*im
  
    !             do i=mbc,mx2-mbc+1
  
    !                 t1=im*(dq1m(i+intwo)-dq1m(i+inone))
    !                 t2=im*(dq1m(i+inone)-dq1m(i      ))
    !                 t3=im*(dq1m(i      )-dq1m(i+ione ))
  
    !                 tt1=13.*t1**2+3.*(   dq1m(i+intwo)-3.*dq1m(i+inone))**2
    !                 tt2=13.*t2**2+3.*(   dq1m(i+inone)+   dq1m(i      ))**2
    !                 tt3=13.*t3**2+3.*(3.*dq1m(i      )-   dq1m(i+ione ))**2
       
    !                 tt1=(epweno+tt1)**2
    !                 tt2=(epweno+tt2)**2
    !                 tt3=(epweno+tt3)**2
    !                 s1 =tt2*tt3
    !                 s2 =6.*tt1*tt3
    !                 s3 =3.*tt1*tt2
    !                 t0 =1./(s1+s2+s3)
    !                 s1 =s1*t0
    !                 s3 =s3*t0
  
    !                 uu(m1,i) = (s1*(t2-t1)+(0.5*s3-0.25)*(t3-t2))/3. &
    !                          +(-q(m,i-2)+7.*(q(m,i-1)+q(m,i))-q(m,i+1))/12.

    !             end do
    !         end do

    !        qr(m,mbc-1:mx2-mbc  )=uu(1,mbc:mx2-mbc+1)
    !        ql(m,mbc  :mx2-mbc+1)=uu(2,mbc:mx2-mbc+1)

    !     end do

    !   return
    !   end subroutine weno5

    ! ===================================================================
    subroutine weno5_char(q,ql,qr,evl,evr)
    ! ===================================================================

        ! This one uses characteristic decomposition
        !  evl, evr are left and right eigenvectors at each interface

        implicit double precision (a-h,o-z)

        double precision, intent(in) :: q(:,:)
        double precision, intent(out) :: ql(:,:),qr(:,:)
        double precision, intent(in) :: evl(:,:,:),evr(:,:,:)

        integer, parameter :: mbc=3
        integer :: meqn, mx2

        mx2  = size(q,2); meqn = size(q,1)

        ! loop over all equations (all components).  
        ! the reconstruction is performed using characteristic decomposition

        forall(m=1:meqn,i=2:mx2)
            ! compute and store the differences of the cell averages
            dq(m,i)=q(m,i)-q(m,i-1)
        end forall

        forall(m=1:meqn,i=3:mx2-1)
            ! Compute the part of the reconstruction that is
            ! stencil-independent
            qr(m,i-1) = (-q(m,i-2)+7.*(q(m,i-1)+q(m,i))-q(m,i+1))/12.
            ql(m,i)   = qr(m,i-1)
        end forall

        do ip=1,meqn

            ! Project the difference of the cell averages to the
            ! 'm'th characteristic field

        
            do m2 = -2,2
               do  i = mbc+1,mx2-2
                  hh(m2,i) = 0.d0
                  do m=1,meqn 
                    hh(m2,i) = hh(m2,i)+ evl(ip,m,i)*dq(m,i+m2)
                  enddo
               enddo
            enddo


            ! the reconstruction

            do m1=1,2

                ! m1=1: construct ql
                ! m1=2: construct qr

                im=(-1)**(m1+1)
                ione=im
                inone=-im
                intwo=-2*im
  
                do i=mbc,mx2-mbc+1
      
                    t1=im*(hh(intwo,i)-hh(inone,i))
                    t2=im*(hh(inone,i)-hh(0,i    ))
                    t3=im*(hh(0,i    )-hh(ione,i ))
      
                    tt1=13.*t1**2+3.*(   hh(intwo,i)-3.*hh(inone,i))**2
                    tt2=13.*t2**2+3.*(   hh(inone,i)+   hh(0,i    ))**2
                    tt3=13.*t3**2+3.*(3.*hh(0,i    )-   hh(ione,i ))**2

                    tt1=(epweno+tt1)**2
                    tt2=(epweno+tt2)**2
                    tt3=(epweno+tt3)**2
                    s1 =tt2*tt3
                    s2 =6.*tt1*tt3
                    s3 =3.*tt1*tt2
                    t0 =1./(s1+s2+s3)
                    s1 =s1*t0
                    s3 =s3*t0
      
                    uu(m1,i) = ( s1*(t2-t1) + (0.5*s3-0.25)*(t3-t2) ) /3.

                end do !end loop over interfaces
            end do !end loop over which side of interface

                ! Project to the physical space:
            do m = 1,meqn
                do i=mbc,mx2-mbc+1
                    qr(m,i-1) = qr(m,i-1) + evr(i,m,ip)*uu(1,i)
                    ql(m,i  ) = ql(m,i  ) + evr(i,m,ip)*uu(2,i)
                enddo
            enddo
        enddo !end loop over waves

      return
      end subroutine weno5_char

    ! ===================================================================
    subroutine weno5_trans(q,ql,qr,evl,evr)
    ! ===================================================================

        ! Transmission-based WENO reconstruction

        implicit double precision (a-h,o-z)

        double precision, intent(in) :: q(:,:)
        double precision, intent(out) :: ql(:,:),qr(:,:)
        double precision, intent(in) :: evl(:,:,:),evr(:,:,:)

        integer, parameter :: mbc=3
        integer :: meqn, mx2

        mx2  = size(q,2); meqn = size(q,1)


        ! the reconstruction is performed using characteristic decomposition

        do m=1,meqn
            ! compute and store the differences of the cell averages
            forall (i=2:mx2)
                dq(m,i)=q(m,i)-q(m,i-1)
            end forall
        enddo

        ! Find wave strengths at each interface
        ! 'm'th characteristic field
        do mw=1,meqn
            do i = 2,mx2
                gg(mw,i) = 0.d0
                do m=1,meqn
                    gg(mw,i) = gg(mw,i)+ evl(mw,m,i)*dq(m,i)
                enddo
            enddo
        enddo

        do mw=1,meqn
            ! Project the waves to the
            ! 'm'th characteristic field

            do m1 = -2,2
                do  i = mbc+1,mx2-2
                    hh(m1,i) = 0.d0
                    do m=1,meqn 
                        hh(m1,i) = hh(m1,i)+evl(mw,m,i)* &
                                    gg(i+m1,mw)*evr(i+m1,m,mw)
                    enddo
                enddo
            enddo

            ! the reconstruction

            do m1=1,2
                ! m1=1: construct ql
                ! m1=2: construct qr
                im=(-1)**(m1+1)
                ione=im; inone=-im; intwo=-2*im
  
                do i=mbc,mx2-mbc+1
  
                    t1=im*(hh(intwo,i)-hh(inone,i))
                    t2=im*(hh(inone,i)-hh(0,i    ))
                    t3=im*(hh(0,i    )-hh(ione,i ))
  
                    tt1=13.*t1**2+3.*(   hh(intwo,i)-3.*hh(inone,i))**2
                    tt2=13.*t2**2+3.*(   hh(inone,i)+   hh(0,i    ))**2
                    tt3=13.*t3**2+3.*(3.*hh(0,i    )-   hh(ione,i ))**2
       
                    tt1=(epweno+tt1)**2
                    tt2=(epweno+tt2)**2
                    tt3=(epweno+tt3)**2
                    s1 =tt2*tt3
                    s2 =6.*tt1*tt3
                    s3 =3.*tt1*tt2
                    t0 =1./(s1+s2+s3)
                    s1 =s1*t0
                    s3 =s3*t0
  
                    u(mw,m1,i) = ( s1*(t2-t1) + (0.5*s3-0.25)*(t3-t2) ) /3.

                enddo
            enddo
        enddo

        ! Project to the physical space:

        do m1 =  1,2
            do m =  1, meqn
                do i = mbc,mx2-mbc+1
                    uh(m,m1,i) =( -q(m,i-2) + 7*( q(m,i-1)+q(m,i) ) &
                                         - q(m,i+1) )/12.
                    do mw=1,meqn 
                        uh(m,m1,i) = uh(m,m1,i) + evr(m,mw,i)*u(mw,m1,i)
                    enddo
                enddo
            enddo
        enddo

        qr(1:meqn,mbc-1:mx2-mbc) = uh(1:meqn,1,mbc:mx2-mbc+1)
        ql(1:meqn,mbc:mx2-mbc+1) = uh(1:meqn,2,mbc:mx2-mbc+1)

        return
    end subroutine weno5_trans

    ! ===================================================================
    subroutine weno5_wave(q,ql,qr,wave)
    ! ===================================================================

        !  Fifth order WENO reconstruction, based on waves
        !  which are later interpreted as slopes.

        implicit double precision (a-h,o-z)

        double precision, intent(in) :: q(:,:)
        double precision, intent(out) :: ql(:,:),qr(:,:)
        double precision, intent(in) :: wave(:,:,:)
        double precision u(2)

        integer, parameter :: mbc=3
        integer :: meqn, mx2

        mx2  = size(q,2); meqn = size(q,1); mwaves=size(wave,2)

        ! loop over interfaces (i-1/2)
        do i=2,mx2
            ! Compute the part of the reconstruction that is stencil-independent
            do m=1,meqn
                qr(m,i-1) = (-q(m,i-2)+7.*(q(m,i-1)+q(m,i))-q(m,i+1))/12.
                ql(m,i)   = qr(m,i-1)
            enddo
            ! the reconstruction is performed in terms of waves
            do mw=1,mwaves
                ! loop over which side of x_i-1/2 we're on
                do m1=1,2
                    ! m1=1: construct q^-_{i-1/2}
                    ! m1=2: construct q^+_{i-1/2}
                    im=(-1)**(m1+1)
                    ione=im; inone=-im; intwo=-2*im
  
                    wnorm2 = wave(1,mw,i      )*wave(1,mw,i)
                    theta1 = wave(1,mw,i+intwo)*wave(1,mw,i)
                    theta2 = wave(1,mw,i+inone)*wave(1,mw,i)
                    theta3 = wave(1,mw,i+ione )*wave(1,mw,i)
                    do m=2,meqn
                        wnorm2 = wnorm2 + wave(m,mw,i      )*wave(m,mw,i)
                        theta1 = theta1 + wave(m,mw,i+intwo)*wave(m,mw,i)
                        theta2 = theta2 + wave(m,mw,i+inone)*wave(m,mw,i)
                        theta3 = theta3 + wave(m,mw,i+ione )*wave(m,mw,i)
                    enddo

                    t1=im*(theta1-theta2)
                    t2=im*(theta2-wnorm2)
                    t3=im*(wnorm2-theta3)
  
                    tt1=13.*t1**2+3.*(theta1   -3.*theta2)**2
                    tt2=13.*t2**2+3.*(theta2   +   wnorm2)**2
                    tt3=13.*t3**2+3.*(3.*wnorm2-   theta3)**2
       
                    tt1=(epweno+tt1)**2
                    tt2=(epweno+tt2)**2
                    tt3=(epweno+tt3)**2
                    s1 =tt2*tt3
                    s2 =6.*tt1*tt3
                    s3 =3.*tt1*tt2
                    t0 =1./(s1+s2+s3)
                    s1 =s1*t0
                    s3 =s3*t0
  
                    if(wnorm2.gt.1.e-14) then
                        u(m1) = ( s1*(t2-t1) + (0.5*s3-0.25)*(t3-t2) ) /3.
                        wnorm2=1.d0/wnorm2
                    else
                        u(m1) = 0.d0
                        wnorm2=0.d0
                    endif
                enddo !end loop over which side of interface
                do m=1,meqn
                    qr(m,i-1) = qr(m,i-1) +  u(1)*wave(m,mw,i)*wnorm2
                    ql(m,i  ) = ql(m,i  ) +  u(2)*wave(m,mw,i)*wnorm2
                enddo
            enddo !loop over waves
        enddo !loop over interfaces

    end subroutine weno5_wave

    ! ===================================================================
    subroutine weno5_fwave(q,ql,qr,fwave,s)
    ! ===================================================================
    !
    !  Fifth order WENO reconstruction, based on f-waves
    !  that are interpreted as slopes.
!

      implicit double precision (a-h,o-z)

      double precision, intent(in) :: q(:,:)
      double precision, intent(inout) :: fwave(:,:,:), s(:,:)
      double precision, intent(out) :: ql(:,:), qr(:,:)
      double precision  u(20,2)

      integer, parameter :: mbc=3
      integer :: meqn, mx2

      mx2= size(q,2); meqn = size(q,1); mwaves=size(fwave,2)

      ! convert fwaves to waves by dividing by the sound speed
      ! We do this in place to save memory
      ! and get away with it because the waves are never used again
      forall(i=1:mx2,mw=1:mwaves,m=1:meqn)
          fwave(m,mw,i)=fwave(m,mw,i)/s(mw,i)
      end forall

      ! loop over interfaces (i-1/2)
      do i=2,mx2
        ! Compute the part of the reconstruction that is
        !  stencil-independent
        do m=1,meqn
          qr(m,i-1) = q(m,i-1)
          ql(m,i  ) = q(m,i)
        enddo
        ! the reconstruction is performed in terms of waves
        do mw=1,mwaves
         ! loop over which side of x_i-1/2 we're on
          do m1=1,2
            ! m1=1: construct q^-_{i-1/2}
            ! m1=2: construct q^+_{i-1/2}

            im=(-1)**(m1+1)
            ione=im; inone=-im; intwo=-2*im
  
            ! compute projections of waves in each family
            ! onto the corresponding wave at the current interface
            wnorm2 = fwave(1,mw,i      )*fwave(1,mw,i)
            theta1 = fwave(1,mw,i+intwo)*fwave(1,mw,i)
            theta2 = fwave(1,mw,i+inone)*fwave(1,mw,i)
            theta3 = fwave(1,mw,i+ione )*fwave(1,mw,i)
            do m=2,meqn
              wnorm2 = wnorm2 + fwave(m,mw,i      )*fwave(m,mw,i)
              theta1 = theta1 + fwave(m,mw,i+intwo)*fwave(m,mw,i)
              theta2 = theta2 + fwave(m,mw,i+inone)*fwave(m,mw,i)
              theta3 = theta3 + fwave(m,mw,i+ione )*fwave(m,mw,i)
            enddo
!
             t1=im*(theta1-theta2)
             t2=im*(theta2-wnorm2)
             t3=im*(wnorm2-theta3)
  
             tt1=13.*t1**2+3.*(theta1   -3.*theta2)**2
             tt2=13.*t2**2+3.*(theta2   +   wnorm2)**2
             tt3=13.*t3**2+3.*(3.*wnorm2-   theta3)**2
       
             tt1=(epweno+tt1)**2
             tt2=(epweno+tt2)**2
             tt3=(epweno+tt3)**2
             s1 =tt2*tt3
             s2 =6.*tt1*tt3
             s3 =3.*tt1*tt2
             t0 =1./(s1+s2+s3)
             s1 =s1*t0
             s3 =s3*t0
  
           if(wnorm2.gt.1.e-14) then
             u(mw,m1) = ( (s1*(t2-t1)+(0.5*s3-0.25)*(t3-t2))/3. &
                       + im*(theta2+6.d0*wnorm2-theta3)/12.d0)
             wnorm2=1.d0/wnorm2
           else
             u(mw,m1) = 0.d0
             wnorm2=0.d0
           endif
          enddo !end loop over which side of interface
          do m=1,meqn
            qr(m,i-1) = qr(m,i-1) +  u(mw,1)*fwave(m,mw,i)*wnorm2
            ql(m,i  ) = ql(m,i  ) +  u(mw,2)*fwave(m,mw,i)*wnorm2
          enddo
        enddo !loop over fwaves
      enddo !loop over interfaces

    end subroutine weno5_fwave

    ! ===================================================================
    subroutine tvd2(q,ql,qr,mthlim)
    ! ===================================================================
    ! Second order TVD reconstruction

        implicit double precision (a-h,o-z)

        double precision, intent(in) :: q(:,:)
        integer, intent(in) :: mthlim(:)
        double precision, intent(out) :: ql(:,:),qr(:,:)
        integer, parameter :: mbc=2
        integer :: meqn, mx2

        mx2  = size(q,2); meqn = size(q,1); 

        ! loop over all equations (all components).  
        ! the reconstruction is performed component-wise

        do m=1,meqn

            ! compute and store the differences of the cell averages

            do i=mbc+1,mx2-mbc
                dqm=dqp
                dqp=q(m,i+1)-q(m,i)
                r=dqp/dqm

                select case(mthlim(m))
                case(1)
                    ! minmod
                    qlimitr = dmax1(0.d0, dmin1(1.d0, r))
                case(2)
                    ! superbee
                    qlimitr = dmax1(0.d0, dmin1(1.d0, 2.d0*r), dmin1(2.d0, r))
                case(3)
                    ! van Leer
                    qlimitr = (r + dabs(r)) / (1.d0 + dabs(r))
                case(4)
                    ! monotonized centered
                    c = (1.d0 + r)/2.d0
                    qlimitr = dmax1(0.d0, dmin1(c, 2.d0, 2.d0*r))
                case(5)
                    ! Cada & Torrilhon simple
                    beta=2.d0
                    xgamma=2.d0
                    alpha=1.d0/3.d0
                    pp=(2.d0+r)/3.d0
                    amax = dmax1(-alpha*r,0.d0,dmin1(beta*r,pp,xgamma))
                    qlimitr = dmax1(0.d0, dmin1(pp,amax))
                end select

           qr(m,i) = q(m,i) + 0.5d0*qlimitr*dqm
           ql(m,i) = q(m,i) - 0.5d0*qlimitr*dqm

         enddo
      enddo

      return
      end subroutine tvd2


    ! ===================================================================
    subroutine tvd2_char(q,ql,qr,mthlim,evl,evr)
    ! ===================================================================

        ! Second order TVD reconstruction for WENOCLAW
        ! This one uses characteristic decomposition

        !  evl, evr are left and right eigenvectors at each interface
        implicit double precision (a-h,o-z)

        double precision, intent(in) :: q(:,:)
        integer, intent(in) :: mthlim(:)
        double precision, intent(out) :: ql(:,:),qr(:,:)
        double precision, intent(in) :: evl(:,:,:),evr(:,:,:)
        integer, parameter :: mbc=2
        integer :: meqn, mx2

        mx2  = size(q,2); meqn = size(q,1); 

        ! loop over all equations (all components).  
        ! the reconstruction is performed using characteristic decomposition

        ! compute and store the differences of the cell averages
        forall(m=1:meqn,i=2:mx2)
            dq(m,i)=q(m,i)-q(m,i-1)
        end forall

        do m=1,meqn

            ! Project the difference of the cell averages to the
            ! 'm'th characteristic field
            do m1 = -1,1
                do  i = mbc+1,mx2-1
                    hh(m1,i) = 0.d0
                    do mm=1,meqn
                        hh(m1,i) = hh(m1,i)+ evl(m,mm,i)*dq(mm,i+m1)
                    enddo
                enddo
            enddo


            ! the reconstruction
            do m1=1,2
                im=(-1)**(m1+1)
                ! m1=1: construct qr_i-1
                ! m1=2: construct ql_i

                do i=mbc+1,mx2-1
                    ! dqp=hh(m1-1,i)
                    ! dqm=hh(m1-2,i)
                    if (dabs(hh(m1-2,i)).gt.1.e-14) then
                        r=hh(m1-1,i)/hh(m1-2,i)
                    else
                        r=0.d0
                    endif
               
                    select case(mthlim(m))
                    case(1)
                        ! minmod
                        slimitr = dmax1(0.d0, dmin1(1.d0, r))
                    case(2)
                        ! superbee
                        slimitr = dmax1(0.d0, dmin1(1.d0, 2.d0*r), dmin1(2.d0, r))
                    case(3)
                        ! van Leer
                        slimitr = (r + dabs(r)) / (1.d0 + dabs(r))
                    case(4)
                        ! monotonized centered
                        c = (1.d0 + r)/2.d0
                        slimitr = dmax1(0.d0, dmin1(c, 2.d0, 2.d0*r))
                    case(5)
                        ! Cada & Torrilhon simple
                        beta=2.d0
                        xgamma=2.d0
                        alpha=1.d0/3.d0
                        pp=(2.d0+r)/3.d0
                        amax = dmax1(-alpha*r,0.d0,dmin1(beta*r,pp,xgamma))
                        slimitr = dmax1(0.d0, dmin1(pp,amax))
                    end select
    
                     u(m,m1,i) = im*0.5d0*slimitr*hh(m1-2,i)

                enddo
            enddo
        enddo

        ! Project to the physical space:
        do m =  1, meqn
            do i = mbc+1,mx2-1
                qr(m,i-1)=q(m,i-1)
                ql(m,i  )=q(m,i  )
                do mm=1,meqn 
                    qr(m,i-1) = qr(m,i-1) + evr(m,mm,i)*u(mm,1,i)
                    ql(m,i  ) = ql(m,i  ) + evr(m,mm,i)*u(mm,2,i)
                enddo
            enddo
        enddo
    end subroutine tvd2_char

    ! ===================================================================
    subroutine tvd2_wave(q,ql,qr,wave,s,mthlim)
    ! ===================================================================
        ! Second order TVD reconstruction for WENOCLAW
        ! This one uses projected waves

        implicit double precision (a-h,o-z)

        double precision, intent(in) :: q(:,:)
        integer, intent(in) :: mthlim(:)
        double precision, intent(out) :: ql(:,:),qr(:,:)
        double precision, intent(in) :: wave(:,:,:), s(:,:)
        integer, parameter :: mbc=2
        integer :: meqn, mx2

        mx2  = size(q,2); meqn = size(q,1); mwaves=size(wave,2)

        forall(i=2:mx2,m=1:meqn)
            qr(m,i-1) = q(m,i-1)
            ql(m,i  ) = q(m,i  )
        end forall

        ! loop over all equations (all components).  
        ! the reconstruction is performed using characteristic decomposition

        do mw=1,mwaves
            dotr = 0.d0
            do i=mbc,mx2-mbc
                wnorm2=0.d0
                dotl=dotr
                dotr=0.d0
                do m=1,meqn
                    wnorm2 = wnorm2 + wave(m,mw,i)**2
                    dotr = dotr + wave(m,mw,i)*wave(m,mw,i+1)
                enddo
                if (i.eq.0) cycle
                if (wnorm2.eq.0.d0) cycle
                
                if (s(mw,i).gt.0.d0) then
                    r = dotl / wnorm2
                else
                    r = dotr / wnorm2
                endif

                select case(mthlim(mw))
                    case(1)
                        ! minmod
                        wlimitr = dmax1(0.d0, dmin1(1.d0, r))
                    case(2)
                        ! superbee
                        wlimitr = dmax1(0.d0, dmin1(1.d0, 2.d0*r), dmin1(2.d0, r))
                    case(3)
                        ! van Leer
                        wlimitr = (r + dabs(r)) / (1.d0 + dabs(r))
                    case(4)
                        ! monotonized centered
                        c = (1.d0 + r)/2.d0
                        wlimitr = dmax1(0.d0, dmin1(c, 2.d0, 2.d0*r))
                    case(5)
                        ! Cada & Torrilhon simple
                        beta=2.d0
                        xgamma=2.d0
                        alpha=1.d0/3.d0
                        pp=(2.d0+r)/3.d0
                        amax = dmax1(-alpha*r,0.d0,dmin1(beta*r,pp,xgamma))
                        wlimitr = dmax1(0.d0, dmin1(pp,amax))
                end select

                uu(mw,i) = 0.5d0*wlimitr

                do m =  1, meqn
                    qr(m,i-1) = qr(m,i-1) + wave(m,mw,i)*uu(mw,i)
                    ql(m,i  ) = ql(m,i  ) - wave(m,mw,i)*uu(mw,i)
                enddo ! end loop over equations

            enddo
        enddo !end loop over waves

      return
      end subroutine tvd2_wave

end module reconstruct
