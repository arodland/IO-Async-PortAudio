package IO::Async::PortAudio;
use strict;
use warnings;
use base qw(IO::Async::Notifier);
use IO::Async::Timer::Periodic;
use Carp;

sub configure {
  my ($self, %args) = @_;

  if (exists $args{stream}) {
    $self->{stream} = delete $args{stream};
  } else {
    croak "stream is required";
  }

  if (exists $args{stream_type}) {
    my $stream_type = delete $args{stream_type};
    if ($stream_type eq 'r') {
      $self->{want_read} = 1;
    } elsif ($stream_type eq 'w') {
      $self->{want_write} = 1;
    } elsif ($stream_type eq 'rw') {
      $self->{want_read} = 1;
      $self->{want_write} = 1;
    } else {
      croak "unknown stream_type";
    }
  } else {
    croak "stream_type is required";
  }

  if (exists $args{frames_per_buffer}) {
    $self->{frames_per_buffer} = delete $args{frames_per_buffer};
  } else {
    croak "frames_per_buffer is required";
  }

  if (exists $args{sample_rate}) {
    $self->{sample_rate} = delete $args{sample_rate};
  } else {
    croak "sample_rate is required";
  }

  if (exists $args{on_read}) {
    $self->{on_read} = delete $args{on_read};
  }
  if ($self->{want_read} && !$self->can_event('on_read')) {
    croak 'readable stream provided without on_read callback or ->on_read method';
  }

  if (exists $args{on_writable}) {
    $self->{on_writable} = delete $args{on_writable};
  }
  if ($self->{want_write} && !$self->can_event('on_writable')) {
    croak 'writable stream provided without on_writable callback or ->on_writable method';
  }

  $self->SUPER::configure(%args);
}

sub _add_to_loop {
  my $self = shift;
  my ($loop) = @_;
  $self->{timer} = IO::Async::Timer::Periodic->new(
    interval => 0.5 * $self->{frames_per_buffer} / $self->{sample_rate},
    on_tick => $self->make_event_cb('on_tick'),
    reschedule => 'skip',
  );
  $self->add_child($self->{timer});
  $self->start;
  $self->SUPER::_add_to_loop(@_);
}

sub _remove_from_loop {
  my $self = shift;
  my ($loop) = @_;
  $self->stop;
  $self->remove_child($self->{timer});
  $self->SUPER::_remove_from_loop(@_);
}

sub start {
  my ($self) = shift;
  $self->{stream}->start;
  $self->{timer}->start;
}

sub stop {
  my ($self) = shift;
  $self->{timer}->stop;
  $self->{stream}->stop;
}

sub on_tick {
  my ($self) = shift;

  if ($self->{want_read}) {
    my $buf;

    while ($self->{stream}->read_available >= $self->{frames_per_buffer}) {
      $self->{stream}->read($buf, $self->{frames_per_buffer});
      $self->invoke_event('on_read', $buf);
    }
  }
  if ($self->{want_write}) {
    if ((!$self->{notified_writable}) && ($self->{stream}->write_available >= $self->{frames_per_buffer})) {
      $self->{notified_writable} = 1;
      $self->invoke_event('on_writable');
    }
  }
}

sub write {
  my ($self) = shift;
  my ($buf) = @_;

  $self->{stream}->write($buf);
  # Re-check write_available immediately so that a client can buffer audio faster than the tick rate
  if ($self->{want_write} && $self->{stream}->write_available >= $self->{frames_per_buffer}) {
    $self->loop->later(sub { $self->invoke_event('on_writable') });
  } else {
    $self->{notified_writable} = 0;
  }
}

1;
