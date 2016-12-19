#!/usr/bin/perl
use strict;
use warnings;
use Audio::PortAudio;
use IO::Async::Loop;
use IO::Async::PortAudio;

my $loop = IO::Async::Loop->new;
my $pa = Audio::PortAudio::default_host_api();
my ($input, $output);

my $writable = 0;
my $buf = "";

sub do_write {
  return unless $writable && length $buf;
  $output->write(substr($buf, 0, 2000, ''));
  $writable = 0;
}

$input = IO::Async::PortAudio->new(
  stream => $pa->default_input_device->open_read_stream(
    {
      channel_count => 1,
      sample_format => 'int16',
    },
    16000,
    1000,
    0,
  ),
  stream_type => 'r',
  sample_rate => 16000,
  frames_per_buffer => 1000,
  on_read => sub {
    my ($self, $data) = @_;
    $buf .= $data;
    do_write;
  },
);
$loop->add($input);

$output = IO::Async::PortAudio->new(
  stream => $pa->default_output_device->open_write_stream(
    {
      channel_count => 1,
      sample_format => 'int16',
    },
    16000,
    4000,
    0,
  ),
  stream_type => 'w',
  sample_rate => 16000,
  frames_per_buffer => 4000,
  on_writable => sub {
    $writable = 1;
    do_write;
  }
);
$loop->add($output);

my $count = 0;
my $timer = IO::Async::Timer::Periodic->new(
  interval => 1,
  on_tick => sub {
    print $count++, "\n";
  }
);
$timer->start;
$loop->add($timer);

$loop->run;
