# use strict;
# use warnings;
# use v5.15;

# $\ = "\n";
# my $i = 1;

# while ($i ne '7') {
# 	$i ++;
# 	# undef $var;
# 	# $var = '3';
# 	my $var;

# 	given ($var)
# 	{
# 		when ('3') {
# 			print "Now $var";
# 		}

# 		default {
# 			print "Default is now!";
# 			$var = '3';
# 		}
# 	}
# }
########################################################

# use warnings;
# use strict;

# use Term::ProgressBar;

# my $total = 50;
# my $progress_bar = Term::ProgressBar->new($total);


# for my $i (1 .. $total) {

#   sleep (1);

#   $progress_bar->update($i);

# }
########################################

#!/usr/bin/perl
#################################################################
# 	Title	:	UDP Client script								# 
#	Authors	: 													#
#	Description:												#
#																#
#		 	 				_________________________________	#
#		Packet structure:  | command | number | data | [CRC] |	#
#						    ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾	#
#################################################################
# use strict;
# use warnings;

# use IO::Socket::INET;         	# Module that adds the socket support
# use File::Basename;				# Module for extracting file name from the path
# use MIME::Base64;				# Module for encoding binary data
# use IO::Poll qw( POLLIN ); 		# Module for ARQ realization: for data detection in a receiving buffer
# use Fcntl qw( SEEK_SET );		# Declaration of SEEK_SET flag for file seeking
# use POSIX;						# For support of math functions
# use String::CRC32 qw( crc32 );
# use Term::ProgressBar;
# use Time::HiRes qw( gettimeofday tv_interval );
# use v5.14;

# $\ = "\n";				# Added as an invisible last element to the parameters passed to the print() function. *doc
# $| = 1;					# If nonzero, will flush the output buffer after every write() or print() function. Normally, it is set to 0. *doc
				
# my $udpPort = '8849';							# Variable for port number defenition
# my $tcpPort = '8850';
# my ( $fileName, $fileSize, $windowsCount, %fileParts ); # Some global variables
# my ( $dataSocket, $serviceSocket );
# my ( $buffer, @window, @arq );
# my $blockSize = 4096;						# Definding of packet portion for transmittion
# my $windowSize = 80;						# ARQ Window size 
# my $timeout = 0.7;
# my $delim = ';';

# print "======= File transfer on Perl ========";
# $dataSocket = IO::Socket::INET->new (
# 		LocalPort 	=> $udpPort,
# 		Proto 		=> 'udp',
# 		Type		=> SOCK_DGRAM
# 		Reuse 		=> 1,
# 		Timeout 	=> 0.1
# 	) or die "Could not start the server on port $udpPort : $!";
# my $serverTcp = IO::Socket::INET->new (
# 		LocalPort	=> $tcpPort,
# 		Proto 		=> 'tcp',
# 		Type		=> SOCK_STREAM,
# 		Reuse 		=> 1,
# 		Timeout 	=> 0.1
# 		Listen 		=> 1
# 	) or die "Couldn't create TCP socket on port $tcpPort : $!";

# $serviceSocket = $serverTcp->accept();
# my $prog = Term::ProgressBar->new ( 15000 );

# ##		Starting the receiving loop that is controlled by 	##
# ##		commands from the client via Switch-like statment	##
# while () 
# {
# 	my $cmd;
# 	my @msg;
# 	my $ts0 = [ gettimeofday ];
# 	# if ( checkService() ) {
# 		$serviceSocket->recv ( $buffer, 5000 );
# 		@msg = split $delim, $buffer;
# 		$cmd = shift @msg;
# 	# }
# 	print "For TCP->Receive : " . tv_interval ($ts0);
# 	given ($cmd)
# 	{
# 		when ('INFO') {
# 			$fileName = shift @msg;
# 			$fileSize = shift @msg;
# 			print "$fileSize bytes of $fileName to be received...";
# 		}
# 		when ('WINDOW') {
# 			my @nums = sort ();
# 			@arq = undef;
# 			for (my $i = 0; $i < $#nums; $i++)
# 			{
# 				if ($nums[$i] != $i) {
# 					push $nums[$i], @arq;
# 					print "Append \@arq[$i] with $nums[$i]";
# 				}
# 			}

# 			my @msg = ('ARQ', ':', join (':', @arq));
# 			$serviceSocket->send ( join (';', @msg) );
# 		}
# 		default {
# 			$ts0 = [ gettimeofday ];
# 			# if ( checkData() ) {
# 				$dataSocket->recv ( $buffer, 9000 );
				
# 				my @msg = split $delim, $buffer;
# 				my $num = shift @msg;
# 				my $encoded = shift @msg;
# 				my $cksum = shift @msg;
# 				my $data = decode_base64 ( $encoded );

# 				if ( $cksum eq crc32 ($data) ){
# 					$fileParts{ $num } = $data;	
# 				}
# 				print "$num) -- " . length($data) . " bytes of file received!";
# 			# }

# 			print "For UDP->Receive : " . tv_interval ($ts0);
# 		}
# 	}
# 	undef $cmd;
# 	undef $buffer;
# 	undef @msg;
# }

# close $dataSocket;
# close $serviceSocket;

# #################

# sub checkIncome {
# 	my $poll = IO::Poll->new;
# 	$poll->mask ( 
# 			$serviceSocket => POLLIN,
# 			$dataSocket    => POLLIN 
# 		);
# 	my $result = $poll->poll ();

# 	if ( $result == -1 ) {
# 		print "Error with poll() : $!";
# 		return 0;
# 	}

# 	return $poll->handles( POLLIN );
# }

# sub checkService {
# 	my $time = shift || 0.125;
# 	my $poll = IO::Poll->new;
# 	$poll->mask (
# 		$serviceSocket => POLLIN
# 	);

# 	my $res = $poll->poll ( $time );
# 	if ( $res == -1 ) {
# 		print "Error with poll() : $!";
# 		return 0;
# 	}

# 	return $res;
# }

# sub checkData {
# 	my $time = shift || 0.125;
# 	my $poll = IO::Poll->new;
# 	$poll->mask (
# 		$dataSocket => POLLIN
# 	);

# 	my $res = $poll->poll ( $time );
# 	if ( $res == -1 ) {
# 		print "Error with poll() : $!";
# 		return 0;
# 	}

# 	return $res;
# }

#!/usr/bin/perl
#################################################################
# 	Title	:	UDP Client script								# 
#	Authors	: 													#
#	Description:												#
#																#
#		 	 				_________________________________	#
#		Packet structure:  | command | number | data | [CRC] |	#
#						    ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾	#
#################################################################
# use strict;
use warnings;

use IO::Socket::INET;         	# Module that adds the socket support
use File::Basename;				# Module for extracting file name from the path
use MIME::Base64;				# Module for encoding binary data
use IO::Poll qw( POLLIN ); 		# Module for ARQ realization: for data detection in a receiving buffer
use Fcntl qw( SEEK_SET );		# Declaration of SEEK_SET flag for file seeking
use POSIX;						# For support of math functions
use String::CRC32 qw( crc32 );
use Time::HiRes qw( gettimeofday tv_interval );
# no strict "subs";
use v5.14;

$\ = "\n";				# Added as an invisible last element to the parameters passed to the print() function. *doc
$| = 1;					# If nonzero, will flush the output buffer after every write() or print() function. Normally, it is set to 0. *doc
				
my $udpPort = '8849';							# Variable for port number defenition
my $tcpPort = '8850';
my ( $fileName, $fileSize, $windowsCount, %fileParts ); # Some global variables
my ( $dataSocket, $serviceSocket );
my ( $buffer, @window, @arq );
my $blockSize = 4096;						# Definding of packet portion for transmittion
my $windowSize = 80;						# ARQ Window size 
my $timeout = 0.7;
my $delim = ';';

print "======= File transfer on Perl ========";
$dataSocket = IO::Socket::INET->new (
		LocalPort 	=> $udpPort,
		Proto 		=> 'udp',
		Type		=> SOCK_DGRAM,
		Reuse 		=> 1
	) or die "Could not start the server on port $udpPort : $!";
my $serverTcp = IO::Socket::INET->new (
		LocalPort	=> $tcpPort,
		Proto 		=> 'tcp',
		Type		=> SOCK_STREAM,
		Listen 		=> 1,
		Reuse 		=> 1
	) or die "Couldn't create TCP socket on port $tcpPort : $!";

$serviceSocket = $serverTcp->accept();
if ( $serviceSocket ) {
	my $client = $serviceSocket->peername;
	my ( $port, $iaddr ) = sockaddr_in( $client );
	my $peerName = gethostbyaddr($iaddr, AF_INET);
	my $peerAddress = inet_ntoa($iaddr);
	print "Client $peerName ($peerAddress) is connected!\n";
}
$windowsCount = 0;

##		Starting the receiving loop that is controlled by 	##
##		commands from the client via Switch-like statment	##
while () 
{
	my $cmd;
	my @msg;
	print "-----> TCP Check";
	if ( checkService() ) {
		print "--> TCP Receive!!!!!";
		my $ts0 = [ gettimeofday ];
		$serviceSocket->recv ( $buffer, 5000 );
		@msg = split $delim, $buffer;
		$cmd = shift @msg;
		print "$cmd -> For TCP->recv : ".tv_interval ($ts0);
	}
	# if ( checkData() ) {
	# 			$dataSocket->recv ( $buffer, 9000 );
				
	# 			# my @msg = split $delim, $buffer;
	# 			# my $num = shift @msg;
	# 			# my $encoded = shift @msg;
	# 			# my $cksum = shift @msg;
	# 			# my $data = encode_base64 ( $encoded );

	# 			# if ( $cksum eq crc32( $data ) ) {
	# 			# 	push @window, $num;
	# 			# 	$fileParts{ $num } = $data;	
	# 			# }
	# 			# else {
	# 			# 	push @arq, $num;}

	# 			# 	# 			print " UDP bytes of file received!";
	# 		}
	# print "\n\nCommand: $cmd \n";
	
	given ($cmd)
	{
		when ('INFO') {
			$fileName = shift @msg;
			$fileSize = shift @msg;
			print "$fileSize bytes of $fileName to be received...";
		}
		# when ('CHECK') {
		# 	if ( scalar (@window) < $windowSize ) {
		# 		@window = sort @window;

		# 		#DEBUG
		# 		print "Window sorted: @window";

		# 		for (my $i = $windowsCount * $windowSize + 1; $i <= ($windowsCount + 1) * $windowSize; $i++)
		# 		{
		# 			my $curr = shift (@window);
		# 			if ($i ne $curr) {
		# 				push @arq, $i;
		# 				$i = $curr;
		# 				print "Append \@arq[$i] with $i";
		# 			}
		# 			print "Cycle: $i";
		# 		}
		# 		$serviceSocket->send ( join ($delim, ( 'ARQ', join (':', @arq) )) );
		# 	}
		# 	else {							# Window Success
		# 		serviceSocket->send ('OK');
		# 		$windowsCount++;
		# 		undef @arq;
		# 		undef @window;
		# 	}
		# }

		default {
			# if ( checkData() ) {
				my $ts0 = [gettimeofday];

				$dataSocket->recv ( $buffer, 9000 );
				
				my @msg = split $delim, $buffer;
				my $num = shift @msg;
				my $encoded = shift @msg;
				my $cksum = shift @msg;
				my $data = encode_base64 ( $encoded );

				if ( $cksum eq crc32( $data ) ) {
					push @window, $num;
					$fileParts{ $num } = $data;	
				}
				else {
					push @arq, $num;
				}
				print "$num) -- " . length($encoded) . " bytes of file received!";
			# }
				print "For UDP->rcv : ".tv_interval($ts0);
		}
	}
	undef $cmd;
	undef $buffer;
	undef @msg;
}

close $dataSocket;
close $serviceSocket;

#################

sub checkIncome {
	my $poll = IO::Poll->new;
	$poll->mask ( 
			$serviceSocket => POLLIN,
			$dataSocket    => POLLIN 
		);
	my $result = $poll->poll ();

	if ( $result == -1 ) {
		print "Error with poll() : $!";
		return 0;
	}

	return $poll->handles( POLLIN );
}

sub checkService {
	my $time = shift || 0.05;
	my $poll = IO::Poll->new;
	$poll->mask (
		$serviceSocket => POLLIN
	);

	my $res = $poll->poll ( $time );
	if ( $res == -1 ) {
		print "Error with poll() : $!";
		return 0;
	}
	print "---> Poll res: $res";
	return $res;
}

sub checkData {
	my $time = shift || 0.05;
	my $poll = IO::Poll->new;
	$poll->mask (
		$dataSocket => POLLIN
	);

	my $res = $poll->poll ( $time );
	if ( $res == -1 ) {
		print "Error with poll() : $!";
		return 0;
	}

	return $res;
}