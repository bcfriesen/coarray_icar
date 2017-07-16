submodule(exchangeable_interface) exchangeable_implementation
  use assertions_interface, only : assert, assertions
  implicit none

  integer, parameter :: default_halo_size=1
  integer, save, allocatable :: neighbors(:)
  integer, save :: north_neighbor, south_neighbor, halo_size

contains

  module subroutine const(this,grid_dims,initial_value,halo_width)
    class(exchangeable_t), intent(inout) :: this
    integer, intent(in) :: grid_dims(:)
    real, intent(in) :: initial_value
    integer, intent(in), optional :: halo_width

    integer :: jms,jme

    if (present(halo_width)) then
        halo_size = halo_width
    else
        halo_size = default_halo_size
    end if

    if (allocated(this%local)) deallocate(this%local)
    this%north_boundary = (this_image() == num_images())
    this%south_boundary = (this_image() == 1)


    associate( halo_south => merge(0,halo_size,this%south_boundary), &
               halo_north => merge(0,halo_size,this%north_boundary))
      jms = grid_dims(4)-halo_south
      jme = grid_dims(4)+grid_dims(3)+halo_north-1
      allocate(this%local(grid_dims(1),grid_dims(2),jms:jme),source=initial_value)
    end associate

    allocate( this%halo_south_in( grid_dims(1),grid_dims(2),halo_size)[*], source=initial_value)
    allocate( this%halo_north_in( grid_dims(1),grid_dims(2),halo_size)[*], source=initial_value)

    associate(me=>this_image())
      south_neighbor = me-1
      north_neighbor = me+1
      if (this%north_boundary .and. this%south_boundary) then
        neighbors = [me]
      else if (this%south_boundary) then
        neighbors = [north_neighbor]
      else if (this%north_boundary) then
        neighbors = [south_neighbor]
      else ! internal cells
        neighbors = [me-1,me+1]
      end if
    end associate

  end subroutine

  module subroutine send(this)
    class(exchangeable_t), intent(inout) :: this
    if (.not. this%north_boundary) call this%put_north
    if (.not. this%south_boundary) call this%put_south
  end subroutine

  module subroutine retrieve(this, no_sync)
    class(exchangeable_t), intent(inout) :: this
    logical,               intent(in),   optional :: no_sync

    if (.not. present(no_sync)) then
        sync images( neighbors )
    else
        if (.not. no_sync) then
            sync images( neighbors )
        endif
    endif

    if (.not. this%north_boundary) call this%retrieve_north_halo
    if (.not. this%south_boundary) call this%retrieve_south_halo
  end subroutine

  module subroutine exchange(this)
    class(exchangeable_t), intent(inout) :: this
    if (.not. this%north_boundary) call this%put_north
    if (.not. this%south_boundary) call this%put_south
    sync images( neighbors )
    if (.not. this%north_boundary) call this%retrieve_north_halo
    if (.not. this%south_boundary) call this%retrieve_south_halo
  end subroutine

  module subroutine put_north(this)
      class(exchangeable_t), intent(inout) :: this
      integer :: n
      n = ubound(this%local,3)

      if (assertions) then
        !! gfortran 6.3.0 doesn't check coarray shape conformity with -fcheck=all so we verify with an assertion
        call assert( shape(this%halo_south_in(:,:,:)[north_neighbor]) == shape(this%local(:,:,n-halo_size+1:n)), &
                     "put_north: conformable halo_south_in and local " )
      end if

      this%halo_south_in(:,:,:)[north_neighbor] = this%local(:,:,n-halo_size*2+1:n-halo_size)
    end subroutine

  module subroutine put_south(this)
      class(exchangeable_t), intent(inout) :: this

      integer :: start
      start = lbound(this%local,3)

      if (assertions) then
        !! gfortran 6.3.0 doesn't check coarray shape conformity with -fcheck=all so we verify with an assertion
        call assert( shape(this%halo_north_in(:,:,:)[south_neighbor]) == shape(this%local(:,:,start:start+halo_size-1)), &
                     "put_south: conformable halo_north_in and local " )
      end if
      this%halo_north_in(:,:,:)[south_neighbor] = this%local(:,:,start+halo_size:start+halo_size*2-1)
    end subroutine

  module subroutine retrieve_north_halo(this)
      class(exchangeable_t), intent(inout) :: this

      integer :: n
      n = ubound(this%local,3)

      this%local(:,:,n-halo_size+1:n) = this%halo_north_in
    end subroutine

  module subroutine retrieve_south_halo(this)
      class(exchangeable_t), intent(inout) :: this

      integer :: start
      start = lbound(this%local,3)

      this%local(:,:,start:start+halo_size-1) = this%halo_south_in
    end subroutine

end submodule
