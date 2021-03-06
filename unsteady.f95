subroutine unsteady(gamS,alpha,gamU,up_upper,up_lower)

use constants
use options
use calls

!variables
implicit none

!inputs
complex, intent(in), dimension(N) :: gamS       !rhs of impermeability condition
real, intent(in):: alpha

!outputs
complex, intent(out), dimension(N) :: gamU       !unsteady circulation distribution

!internal variables
real, dimension(2) :: xc
real :: Ux
real :: Uy

complex, dimension(N8,N8) :: zeta_upper
complex, dimension(N8,N8) :: zeta_lower
complex, dimension(N8,N8) :: stencil_upper
complex, dimension(N8,N8) :: stencil_lower
complex, dimension(N8)   :: streamfunction_upper
complex, dimension(N8)   :: streamfunction_lower
complex, dimension(N8)   :: prhs_upper
complex, dimension(N8)   :: prhs_lower

complex, dimension(N)   :: rhs
complex, dimension(N,N) :: a

complex, dimension(N,N) :: psi_upper, psi_lower
complex, dimension(N,N,2) :: vhat_u, vhat_l
complex, dimension(N,2) :: up_upper, up_lower

integer :: poisson_order, i, j, Nx, Ny

!cgeev variables
integer :: info
integer :: lda
complex, dimension(N,N) :: adum
complex, dimension(N)   :: eigval
complex, dimension(N,N) :: eigvecL, eigvecR
complex, dimension(5*N) :: CWORK
real, dimension(2*N)    :: RWORK

!intialise
i = 1
j = 1
Ux = cos(alpha)
Uy = sin(alpha)
Nx = 5*Np+1
Ny = Np+1
poisson_order = Nx*Ny
vhat_u = 0.0
vhat_l = 0.0
xc = 0.0
lda = Np+1

call zeta_field(gamS,Ux,zeta_upper,zeta_lower)

call poisson_matrix(zeta_upper,    zeta_lower, &
                    stencil_upper, stencil_lower, &
                    prhs_upper,    prhs_lower)


streamfunction_upper = solvecomplex8(poisson_order,stencil_upper,prhs_upper)
streamfunction_lower = solvecomplex8(poisson_order,stencil_lower,prhs_lower)

psi_upper(1:Nx,1:Ny) = cvec2mat(poisson_order, Nx, Ny, streamfunction_upper(1:poisson_order))
psi_lower(1:Nx,1:Ny) = cvec2mat(poisson_order, Nx, Ny, streamfunction_lower(1:poisson_order))

call unsteadymatrix(psi_upper,psi_lower,a,rhs,up_upper,up_lower)

adum = a

!call cgeev('V','V', lda, a, N, eigval, eigvecL, N, eigvecR, N, CWORK, size(CWORK), RWORK, info)
!print *, 'eig info', info

a = adum

gamU = solvecomplex(Np+1,a,rhs)

!plot velocity field
if (loop(1).eq.plot(1) .and. loop(2).eq.plot(2) .and. loop(3).eq.plot(3)) then

        call velfield_perturbation(psi_upper, psi_lower, vhat_u, vhat_l)
        
        call velfield_unsteady(vhat_u, vhat_l, gamU)

        !write streamfunction
        do 10 j = Ny,1,-1
                
                xc(2) = -j*dc
                
                do 11 i = 1,Nx
                        
                        xc(1) = -2.0 + (i-1)*dc

                        !               1      2      3                     4
                        write(file3,*) xc(1), xc(2), real(psi_lower(i,j)), aimag(psi_lower(i,j)) &
                        !                             5,6                   7,8
                                                   , real(vhat_l(i,j,1:2)),    aimag(vhat_l(i,j,1:2))
                
                11 continue
                
                write(file3,*) ''
        
        10 continue
        
        do 12 j = 1,Ny
                
                xc(2) = j*dc
                
                do 13 i = 1,Nx
                        
                        xc(1) = -2.0 + (i-1)*dc
                        
                        !               1      2      3                     4
                        write(file3,*) xc(1), xc(2), real(psi_upper(i,j)), aimag(psi_upper(i,j)) &
                        !                             5,6                   7,8
                                                   , real(vhat_u(i,j,1:2)),    aimag(vhat_u(i,j,1:2))
                
                13 continue
                
                write(file3,*) ''

        12 continue

end if


end subroutine unsteady


!------------------------------------------------------------------------------------------


subroutine unsteadymatrix(psi_u,psi_l,a,rhs,up_u,up_l)

use constants
use options
use calls

!variables
implicit none

!inputs
complex, intent(in), dimension(N,N) :: psi_u, psi_l

!outputs
complex, intent(out), dimension(N,N) :: a       !influence matrix
complex, intent(out), dimension(N)   :: rhs     !rhs of unsteady impermeability
complex, intent(out), dimension(N,2) :: up_u, up_l      !pertubation velocities on blade surface

!internal variables
complex, dimension(2) :: u                      !vortex induced velocity
real, dimension(2) :: xv,xc                     !vortex and collocation point
real, dimension(2) :: no,ta                     !panel normal and tangent
real, dimension(2) :: v,c,nor,t                 !dummy
!complex :: afar                                 !far field wake influence
integer :: i,j                                  !counters
integer :: le0                                  !index of leading edge in sf arrays
integer :: Nx,Ny
complex :: phase0, phase, shift

!initialise
a   = 0.0
rhs = 0.0

call panel(Np+1,xv,c,nor,t)
phase0 = exp(imag*kappa*wakestart)
shift  = exp(imag*kappa*dc)


!bound vorticity
a(1:Np,1:Np) = selfinfluence(1:Np,1:Np)

!near field shed vorticity
do 1 i = 1,Np

        !panel influenced
        call panel(i,v,xc,no,ta)

        phase = phase0
        
        do 1 j = Np+1,Nw
                
                call panel(j,xv,c,nor,t)
                
                u = vor2d(xc,xv)
                u = u*phase

                a(i,Np+1) = a(i,Np+1) + dotcr(2,u,no)
                
                phase = phase*shift
        
1 continue

!far field shed vorticity
                !call panel(1,v,xc,no,ta)
                !
                !xc(2) = 0.0
                !
                !nor = [0.0 , 1.0]
                !
                !afar = 0.0
                !
                !do 2 i = Nwfar+1,Nw
                !
                !        call panel(i,xv,c,no,t)
                !        
                !        u = vor2d(xv,xc)
                !        u = u*exp(imag*(xv(1)-1.0)*kappa)
                !        
                !        afar = afar + u(2)
                !
                !2 continue
                !
                !a(1,Np+1) = a(1,Np+1) + afar
                !
                !first and last far field wake vortices v and xv
                !call panel(Nwfar,v,c,no,ta)
                !v(1) = v(1) + dc
                !call panel(Nw,xv,c,no,ta)
                !
                !do 3 i = 2,Np
                !        
                !        !remove old farthest vortex
                !        u = vor2d(xv,xc)
                !        u = u*exp(imag*(xv(1)-1.0)*kappa)
                !
                !        afar = afar - u(2)
                !
                !        !phase shift for coordinate shift to next panel
                !        afar = afar * exp(imag*kappa*dc)
                !        
                !        !include new closest farfield vortex
                !        call panel(i,c,xc,no,ta)
                !
                !        u = vor2d(v,xc)
                !        u = u*exp(imag*(xv(1)-1.0)*kappa)
                !
                !        afar = afar + u(2)
                !
                !        a(i,Np+1) = a(i,Np+1) + afar
                !
                !3 continue

!kelvin condition
!a(Np+1,1:Np) = imag*omega
a(Np+1,1:Np) = (1.0 - exp(imag*omega*dc))

a(Np+1,Np+1) = (1.0 , 0.0)

rhs(Np+1) = 0.0


!unsteady rhs
Nx = 5*Np+1
Ny = Np+1

le0 = 2*Np

do 4 i = 1,Np
        
        !normal velocity
        up_u(i,2) = psi_u(le0+i , 1) - psi_u(le0+i+1 , 1)
        up_l(i,2) = psi_l(le0+i , 1) - psi_l(le0+i+1 , 1)

        !tangential velocity
        up_u(i,1) =             psi_u(le0+i  , 2) - psi_u(le0+i  , 1)
        up_u(i,1) = up_u(i,1) + psi_u(le0+i+1, 2) - psi_u(le0+i+1, 1)
        up_u(i,1) = up_u(i,1) / 2.0
        
        up_l(i,1) =             psi_l(le0+i  , 1) - psi_l(le0+i  , 2)
        up_l(i,1) = up_l(i,1) + psi_l(le0+i+1, 1) - psi_l(le0+i+1, 2)
        up_l(i,1) = up_l(i,1) / 2.0
        
        up_u(i,:) = up_u(i,:)/dc
        up_l(i,:) = up_l(i,:)/dc
        
        !rhs using finite volume poisson solver
        rhs(i) = -( up_u(i,2) + up_l(i,2) ) / 2.0

4 continue


end subroutine unsteadymatrix
