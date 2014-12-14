#!/usr/bin/perl
use IO::Socket::INET;         	# Module that adds the socket support
use MIME::Base64;				# Module for encoding binary data
use IO::Poll qw( POLLIN );		# For asynchronous sockets realization
use v5.12;						# For support of given-when statement

$| = 1;				# Flushing to SOCKET after each write
$\ = "\n";			# Added as an invisible last element to the parameters passed to the print() function. *doc

my $port = '8849';								# Declaring of port number for socket
my ( $buffer, $message, $counter, $peerAddress, $peerName, $fileSize, $fileName, $packetsCount, %fileParts, @arq ); # Global variables declaration

my $socket = IO::Socket::INET->new(				# Initialization of the socket
				LocalPort => $port,		
				Proto => 'udp',
				Type => SOCK_DGRAM
	) or die "Could not start server!!! : $!";

##		Starting the receiving loop that is controlled by 	##
##		commands from the client via Switch-like statment	##

while () {									  	# Endless working loop
	my ( $senderIP, $senderName ) = getIP ($socket->recv ( $message, 2048 )); # Waits untill the packet is received and read socket's buffer to $message
	print length ( $message ) . " bytes from $senderName ($senderIP)";	  
	my @packet = split ';', $message;			# Splitting the packet into array: ( command, numberOfPacket, Data )
	my $cmd = shift @packet;					# Taking command field from packet
	
	 given ($cmd) {								# Switching of the received commands
		when ('NAME') {							# Receiving the information about the file
			$fileSize = pop @packet;			# Taking file size from the packet
			$fileName = pop @packet;			# Taking file name from the packet
			$packetsCount = pop @packet;		# Taking number of the packets to be sent
			if ( tell ( FILE ) != -1 ) {		# Check whether file is opened		
			    close FILE;						# If it is open -> close it
			}
			open FILE, '>', $fileName || die "Can not open file $fileName for writting: $!"; # Open file for writing 
			print "Receiving $fileName ...";
		}
		when ('DATA') {							# Receiving the parts of the file
			receiveData ( @packet );
		}
		when ('CHECK') {						# ARQ realization
			prepareARQ ();						# Check for lost packets
			if ( sendARQ () == 0 ) {			# Request for repeating of the lost parts
				$socket->send ( 'FINISH' );		# If there are no parts to repeat - sending the FINISH message
			}
		}
		when ('FINISH') {
			$counter = 0;						# 
		}
		when ('EXIT') {							# Close the program
			exit;
		}
	 }
}

close $socket;				# Closing the socket
close FILE;					# Closing the file

# ============= Functions ===================#

sub receiveData {
	my ( $num, $encoded ) = @_; 				# Packet number and encoded data from socket as parameters
	my $rawData = decode_base64 ( $encoded );	# Decoding file part from Base64
	
	%fileParts{$num} = $rawData;				# Put file's data into associative array with packet's number as a key
}

sub prepareARQ {								# Checking for the lost packets
	my $count = 0;								# Just a counter	
	undef @arq;
	for ( my $i = 1; $i <= $packetsCount; $i++ ) {		# Loop for checking the lost packets
		my $ok = 0;								# Flag for marking found parts  
		foreach my $k ( keys %fileParts ) {		# Going through the all received parts' numbers
			if ( $i == $k ) {					# Find out the current order number of the part	 
				$ok = 1;						# If statement is true - mark as a found				
				break;							# Stop the loop of searching	
			}
		}
		if ( $ok ) {							# If previous actions are successfull - go forward
			continue;
		}
		else {									# If not ->
			push @arq, $i;						# 	append them to the ARQ queue
		}
	}
}

sub sendARQ {									# Request for repeating of the lost parts 
	my $count = @arq;							# Counting the number of packets necessary to be repeated
	if ($count == 0) {
		return 0;
	}
	my @msg = ( 'ARQ', shift(@arq), $count );
	$socket->send ( join ';', @msg );

	return $count;
}

sub getIP {												# Utilit function for taking the sender's address 
	my ( $port, $iaddr ) = sockaddr_in ( shift (@_) );	# from sockaddr_in structure
	my $peerAddress = inet_ntoa( $iaddr );				#
	my $peerName = gethostbyaddr ( $iaddr, AF_INET );	#
	
	if ( wantarray() ) {						# List context
		return ( $peerAddress, $peerName );		#
	} 
	elsif ( defined wantarray() ) {				# Scalar context
		return $peerAddress;
	} 
}