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
use strict;
use warnings;

use IO::Socket::INET;         	# Module that adds the socket support
use File::Basename;				# Module for extracting file name from the path
use MIME::Base64;				# Module for encoding binary data
use IO::Poll qw( POLLIN ); 		# Module for ARQ realization: for data detection in a receiving buffer
use Fcntl qw( SEEK_SET );		# Declaration of SEEK_SET flag for file seeking
use POSIX;						# For support of math functions

$\ = "\n";				# Added as an invisible last element to the parameters passed to the print() function. *doc
$| = 1;					# If nonzero, will flush the output buffer after every write() or print() function. Normally, it is set to 0. *doc
				
my $argc = @ARGV;				# Checking the number of arguments
if ($argc < 1) {				# If there is no arguments ->
	HELP_MESSAGE();				# 			print the help message
	exit;						# Exit
}
my $port = '8849';							# Variable for port number defenition
my $srvPort = '8850'
my $fileName = fileparse ( $filePath );		# Extracting the name of the file
my ( $buffer, $number, $partsCount, @arq, %fileParts ); # Some global variables
my ( $dataSocket, $serviceSocket );
my $blockSize = 4096;						# Definding of packet portion for transmittion
my $fileSize = -s $filePath;				# Taking the size of the local file (-s is a size operator)
my $windowSize = 80;						# ARQ Window size 
my $timeout = 0.7;
my $delim = ';';

print "======= File transfer on Perl ========";
$dataSocket = IO::Socket::INET->new (
		LocalPort 	=> $port,
		Proto 		=> 'udp',
		Type		=> SOCK_DGRAM
	) or die "Could not start the server on port $port : $!";
my $serverTcp = IO::Socket::INET->new (
		LocalPort	=> $srvPort,
		Proto 		=> 'tcp',
		Type		=> SOCK_STREAM,
		Listen 		=> 1
	) or die "Couldn't create TCP socket on port $srvPort : $!";

$serviceSocket = $serverTcp->accept();

##		Starting the receiving loop that is controlled by 	##
##		commands from the client via Switch-like statment	##
while () 
{
	# my @socketList = checkIncome ();
	if ( checkService() ) {
		my $rcv = $serviceSocket->recv ( $buffer, 9000 );
	}
	# my ( $port, $iaddr ) = sockaddr_in ( $rcv );
	# my $peerAddress = inet_ntoa ( $iaddr );
	# my $peerName = gethostbyaddr ( $iaddr, AF_INET );
	my @msg = split $delim, $buffer;
	my $cmd = shift @msg;

	print length($message) . " bytes are \'$cmd\' received from $peerAddress ($peerName)";
	# my @packet = split ';', $message;
	# my $cmd = shift @packet;

	given ($cmd)
	{
		when ('INFO') {
			my $num = shift @msg;
			my $fileName = shift @msg;
			my fileSize = shift @msg;
			print "$fileSize bytes of $fileName to be received...";
		}
		when ('WINDOWEnd') {
			my @nums = sort keys %fileParts;
			@arq = undef;
			for ($i = 0; $i < $#nums; $i++)
			{
				if ($nums[$i] != $i) {
					push $nums[$i], @arq;
					print "Append \@arq[$i] with $nums[$i]";
				}
			}

			my @msg = ('ARQ', ':', join (':', @arq));
			$socket->send ( join (';', @msg) );
		}
		default {
			if ( checkUdp() ) {
				$dataSocket->recv ( $buffer, 9000 );
				my @msg = split $delim, $buffer;
				my $num = shift @msg;
				my $encoded = shift @msg;
				print "$num) -- " . length($encoded) . " bytes of file received!";
				$fileParts{$num} = decode_base64 ( $encoded );	
			}
		}
	}
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
	my $time = shift || 0.125;
	my $poll = IO::Poll->new;
	$poll->mask (
			$serviceSocket => POLLIN
		);

	my $res = $poll->poll ( $time );
	if ( $res == -1 ) {
		print "Error with poll() : $!";
		return 0;
	}

	return $res;
}

sub checkUdp {
	my $time = shift || 0.125;
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