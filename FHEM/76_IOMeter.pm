# $Id$
###############################################################################
#
# FHEM Modul für IOMeter 
#
###############################################################################
package main;

use strict;
use warnings;

use HttpUtils;
use JSON;
use Data::Dumper;

use constant VERSION 			=> "v0.0.2";

use constant USERAGENT			=> "Fhem";

sub IOMeter_Initialize($) {
	my ($hash) = @_;

	# Definieren von FHEM-Funktionen
	$hash->{DefFn}		= "IOMeter_Define";
	$hash->{SetFn}		= "IOMeter_Set";
	$hash->{GetFn}		= "IOMeter_Get";
	$hash->{AttrFn}		= "IOMeter_Attr";
    $hash->{AttrList}	= "UpdateInterval expert:0,1 ".$readingFnAttributes;

}

# Definition des Geräts in FHEM
sub IOMeter_Define($$) {
	my ($hash, $def) = @_;
	my @args = split("[ \t][ \t]*", $def);

	return "Usage: define <name> IOMeter <IP> " if (int(@args) != 3);

	my $name			= $args[0];
	$hash->{helper}{ip}	= $args[2];

	$hash->{VERSION}			= VERSION;
	$hash->{DEF} 				= $hash->{helper}{ip};
	$hash->{STATE}				= 'initialized';

	readingsSingleUpdate($hash, 'state', 'initialized', 1 );

	if( $init_done ) {
		InternalTimer(gettimeofday()+3, "IOMeter_Update", $hash);
	}
	else{
		InternalTimer(gettimeofday()+10, "IOMeter_Update", $hash);  
	}

	return undef;
}

sub IOMeter_Update{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	IOMeter_getStatus($hash);
	IOMeter_getReading($hash);
	
	InternalTimer(gettimeofday() + AttrVal($name,"UpdateInterval",300), "IOMeter_Update", $hash) if(AttrVal($name,"UpdateInterval",0));	

	return undef;
}

sub IOMeter_Set($$@) {
	my ($hash, $name, $cmd, @args) = @_;

	my $list = "Update:noArg UpdateReading:noArg UpdateStatus:noArg";

	if ($cmd eq "UpdateReading") {
		IOMeter_getReading($hash);
		return undef;
	}
	elsif($cmd eq "UpdateStatus"){
		IOMeter_getStatus($hash);
		return undef;
	}
	elsif($cmd eq "Update"){
		RemoveInternalTimer($hash, "UpdateInterval");
		IOMeter_Update($hash);
		return undef;
	}

	return "Unknown argument $cmd, choose one of $list";
}


sub IOMeter_getReading{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $url = "http://".$hash->{helper}{ip}."/v1/reading";


	my $body = {};

	# HTTP GET Anfrage senden
	my $header    = {
		"Content-Type"		=> 'application/json',
		"Accept-Language"	=> 'de-DE',
		"User-Agent"		=> USERAGENT,   #
		"Accept"			=> '*/*',
	};

	my $param = {
		"url"			=> $url,
		"method"		=> "GET",
		"timeout"		=> 5,
		"header"		=> $header, 
		"data"			=> "", 
		"hash"			=> $hash,
		"command"		=> "getReading",
		"callback"		=> \&IOMeter_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Request> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}


sub IOMeter_getStatus{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $url = "http://".$hash->{helper}{ip}."/v1/status";

	my $body = {};

	# HTTP GET Anfrage senden
	my $header    = {
		"Content-Type"		=> 'application/json',
		"Accept-Language"	=> 'de-DE',
		"User-Agent"		=> USERAGENT,   #
		"Accept"			=> '*/*',
	};

	my $param = {
		"url"			=> $url,
		"method"		=> "GET",
		"timeout"		=> 5,
		"header"		=> $header, 
		"data"			=> "", 
		"hash"			=> $hash,
		"command"		=> "getStatus",
		"callback"		=> \&IOMeter_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Request> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}


sub IOMeter_parseRequestAnswer {
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	my $responseData;

	my $error	= "not defined";
	my $message	= "not defined";
	my $statusCode	= "not defined";

	if($err ne ""){
		Log3 $name, 1, $name.": error while HTTP requesting ".$param->{url}." - $err"; 
		readingsSingleUpdate($hash, 'state', 'error', 1 );
		return undef;
	}
	elsif($data ne ""){
		Log3 $name, 5, $name.": <parseRequestAnswer> URL:".$param->{url}." returned data:\n".
			"## HTTP-Statuscode ###\n".$param->{code} ."\n".
			"## Data ##############\n".$data."\n".
			"## Header ############\n".$param->{httpheader}."\n";
  
		# $param->{code} auswerten?
		#unless (($param->{code} == 200) || ($param->{code} == 400)){
		unless ($param->{code} == 200){
			Log3 $name, 1, $name.": error while HTTP requesting ".$param->{url}." - code: ".$param->{code}; 
			readingsSingleUpdate($hash, 'state', 'error', 1 );
			return undef;
		}

		# testen ob JSON OK ist
		if($data =~ m/\{.*\}/s){
			eval{
				$responseData = decode_json($data);
				IOMeter_convertBool($responseData);
			};
			if($@){
				my $error = $@;
				$error =~ m/^(.*?)\sat\s(.*?)$/;
				Log3 $name, 1, $name.": error while HTTP requesting of command '".$param->{command}."' - Error while JSON decode: $1 ";
				Log3 $name, 5, $name.": <parseRequestAnswer> JSON decode at: $2";
				readingsSingleUpdate($hash, 'state', 'error', 1 );
				return undef;
			}
			# testen ob Referenz vorhanden
			if(ref($responseData) ne 'HASH') {
				Log3 $name, 1, $name.": error while HTTP requesting of command '".$param->{command}."' - Error, response isn't a reference!";
				readingsSingleUpdate($hash, 'state', 'error', 1 );
				return undef;
			}
		}                                                       

		if($param->{command} eq "getReading") { 
			$hash->{helper}{reading} = $responseData;

			readingsBeginUpdate($hash); 	
	 			readingsBulkUpdate($hash, "meter_number", $hash->{helper}{reading}{meter}{number});
				readingsBulkUpdate($hash, "meter_reading_time", $hash->{helper}{reading}{meter}{reading}{time});
			
				if(defined($hash->{helper}{status}{device}{core}{attachmentStatus})){
					if($hash->{helper}{status}{device}{core}{attachmentStatus} eq "attached"){
						foreach my $registers(@{$hash->{helper}{reading}{meter}{reading}{registers}}){
							if($registers->{obis} eq "01-00:01.08.00*ff"){
								readingsBulkUpdate($hash, "total_energy_consumption", ($registers->{value} / 1000)); # in kWh
							}
							elsif($registers->{obis} eq "01-00:02.08.00*ff"){
								readingsBulkUpdate($hash, "total_energy_production", ($registers->{value} / 1000)); # in kWh
							}
							elsif($registers->{obis} eq "01-00:10.07.00*ff"){
								readingsBulkUpdate($hash, "current_power_consumption", $registers->{value}); # in W
							}
							if(AttrVal($name,"expert",0)){
								readingsBulkUpdate($hash, makeReadingName($registers->{obis}), $registers->{value}." ".$registers->{unit});
							}
						}
						readingsSingleUpdate($hash, 'state', 'connected', 1 );
					}
					else{
						readingsSingleUpdate($hash, 'state', 'disconnected', 1 );
					}
				}
			readingsEndUpdate($hash, 1);

			Log3 $name, 5, $name.": <parseRequestAnswer> core data tried to load!";
			
		}
		elsif($param->{command} eq "getStatus"){
			$hash->{helper}{status} = $responseData;

			$hash->{helper}{status}{meter}{number} = "N/A" if(!defined($responseData->{meter}{number}));
			
			if($hash->{helper}{status}{device}{core}{connectionStatus} eq "connected"){
				$hash->{helper}{status}{device}{core}{batteryLevel} = "N/A" if($hash->{helper}{status}{device}{core}{powerStatus} ne "battery");
				$hash->{helper}{status}{device}{core}{pinStatus} = "N/A" if(!defined($responseData->{device}{core}{pinStatus}));
				$hash->{helper}{status}{device}{core}{attachmentStatus} = "N/A" if(!defined($responseData->{device}{core}{attachmentStatus}));
				
				if($hash->{helper}{status}{device}{core}{attachmentStatus} eq "attached"){
					readingsSingleUpdate($hash, 'state', 'connected', 1 );
				}
				else{
					readingsSingleUpdate($hash, 'state', 'disconnected', 1 );
				}
			}
			else{
				$hash->{helper}{status}{device}{core}{rssi} = "N/A";
				$hash->{helper}{status}{device}{core}{version} = "N/A";
				$hash->{helper}{status}{device}{core}{powerStatus} = "N/A";
				$hash->{helper}{status}{device}{core}{batteryLevel} = "N/A";
				$hash->{helper}{status}{device}{core}{attachmentStatus} = "N/A";
				$hash->{helper}{status}{device}{core}{pinStatus} = "N/A";
				
				readingsSingleUpdate($hash, 'state', 'disconnected', 1 );
			}

			readingsBeginUpdate($hash); 	
	 			readingsBulkUpdate($hash, "meter_number", $hash->{helper}{status}{meter}{number});
	 			readingsBulkUpdate($hash, "device_bridge_rssi", $hash->{helper}{status}{device}{bridge}{rssi});
				readingsBulkUpdate($hash, "device_version", $hash->{helper}{status}{device}{bridge}{version});
				readingsBulkUpdate($hash, "device_id", $hash->{helper}{status}{device}{id});
				readingsBulkUpdate($hash, "device_core_connectionStatus", $hash->{helper}{status}{device}{core}{connectionStatus});
				readingsBulkUpdate($hash, "device_core_rssi", $hash->{helper}{status}{device}{core}{rssi});
				readingsBulkUpdate($hash, "device_core_Version", $hash->{helper}{status}{device}{core}{version});
				readingsBulkUpdate($hash, "device_core_powerStatus", $hash->{helper}{status}{device}{core}{powerStatus});
				readingsBulkUpdate($hash, "device_core_batteryLevel", $hash->{helper}{status}{device}{core}{batteryLevel});
				readingsBulkUpdate($hash, "device_core_attachmentStatus", $hash->{helper}{status}{device}{core}{attachmentStatus});
				readingsBulkUpdate($hash, "device_core_pinStatus", $hash->{helper}{status}{device}{core}{pinStatus});
			readingsEndUpdate($hash, 1);

			Log3 $name, 5, $name.": <parseRequestAnswer> state data tried to load!";

		}
		else{
			Log3 $name, 5, $name.": <parseRequestAnswer> unhandled command $param->{command}";
		}
		
		#readingsSingleUpdate($hash, 'state', 'connected', 1 );
		
		return undef;
	}
	Log3 $name, 1, $name.": error while HTTP requesting URL:".$param->{url}." - no data!";
	return undef;
}


sub IOMeter_Get {
	my ($hash, $name, $opt, @args) = @_;

	return "\"get $name\" needs at least one argument" unless(defined($opt));

	Log3 $name, 5, $name.": <Get> called for $name : msg = $opt";

	my $dump;
	my $usage = "Unknown argument $opt, choose one of Reading:noArg Status:noArg";
	
	if ($opt eq "Reading"){
		if(defined($hash->{helper}{reading})){
	        if(%{$hash->{helper}{reading}}){
	        	IOMeter_convertBool($hash->{helper}{reading});
			    local $Data::Dumper::Deepcopy = 1;
				$dump = Dumper($hash->{helper}{reading});
				$dump =~ s{\A\$VAR\d+\s*=\s*}{};
	        	return "stored data:\n".$dump;
	        }
	    }
		return "No data available: $opt";	
	} 
	elsif($opt eq "Status"){
		if(defined($hash->{helper}{status})){
			if(%{$hash->{helper}{status}}){
				IOMeter_convertBool($hash->{helper}{status});
				local $Data::Dumper::Deepcopy = 1;
				$dump = Dumper($hash->{helper}{status});
				$dump =~ s{\A\$VAR\d+\s*=\s*}{};
				return "stored data:\n".$dump;
			}
		}
		return "No data available: $opt";
	}
	return $usage; 
}

sub IOMeter_Attr {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	# $cmd can be "del" or "set"
	# $name is device name
	# $attr_name and $attr_value are Attribute name and value
	my $hash = $main::defs{$name};
	
	$attr_value = "" if (!defined $attr_value);
	
	Log3 $name, 5, $name.": <Attr> Called for $attr_name : value = $attr_value";
	
	if($cmd eq "set") {
        if($attr_name eq "xxx") {
			# value testen
			#if($attr_value !~ /^yes|no$/) {
			#    my $err = "Invalid argument $attr_value to $attr_name. Must be yes or no.";
			#    Log 3, "xxxxx: ".$err;
			#    return $err;
			#}
		}
		elsif($attr_name eq "UpdateInterval") {
			unless ($attr_value =~ qr/^[0-9]+$/) {
				Log3 $name, 2, $name.": Invalid Time in attr $attr_name : $attr_value";
				return "Invalid Time $attr_value";
			} 
			InternalTimer(gettimeofday() + $attr_value, "IOMeter_Update", $hash) if($attr_value);
		} 

	}
	elsif($cmd eq "del"){
		#default wieder herstellen
		if($attr_name eq "UpdateInterval") {
			RemoveInternalTimer($hash, "UpdateInterval"); 
		} 
	
	}
	return undef;
}

# Convert Bool #################################################################

sub IOMeter_convertBool {

	local *_convert_bools = sub {
		my $ref_type = ref($_[0]);
		if ($ref_type eq 'HASH') {
			_convert_bools($_) for values(%{ $_[0] });
		}
		elsif ($ref_type eq 'ARRAY') {
			_convert_bools($_) for @{ $_[0] };
		}
		elsif (
			   $ref_type eq 'JSON::PP::Boolean'           # JSON::PP
			|| $ref_type eq 'Types::Serialiser::Boolean'  # JSON::XS
		) {
			$_[0] = $_[0] ? 1 : 0;
		}
		else {
			# Nothing.
		}
	};

	&_convert_bools;

}


1;
