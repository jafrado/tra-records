#!/usr/bin/perl
use strict;
use warnings;
use Text::CSV;
use LWP::Simple;
use File::stat;
use Time::localtime;
use Image::Magick;
use CGI qw(escapeHTML);
use URI::Find;
use Scalar::Util qw(looks_like_number);

# Format of Datafile
#Class,Type,Rocket Motor,Total Impulse,Name,Altitude,Altimeters (include GPS model if > 30K),Date,Location,GPS URL,Image URL,Altimeter URL, Notes, Historical
# NOTE: everything needs to move for a new field added
# Offsets for each record above
use constant CLASS => 0;
use constant TYPE => 1;
use constant MOTOR => 2;
use constant TOTAL_IMPULSE => 3;
use constant NAME => 4;
use constant MAX_ALT => 5;
use constant ALTIMETERS => 6;
use constant DATE => 7;
use constant LOCATION => 8;
use constant GPS_URL => 9;
use constant IMG_URL => 10;
use constant ALT_URL => 11;
use constant NOTES => 12;
use constant HISTORICAL => 13;

# Top-level directory where data is stored
# Not: Class (command line option) is appended to this
# Resulting URI element would be $DATADIR/$CLASS
my $TOPDIR = "records/";
my $DATADIR = $TOPDIR."data";
my $URIDIR = "data";

my $csv = Text::CSV->new ({
    binary    => 1, # Allow special character. Always set this
    auto_diag => 1, # Report irregularities immediately
});

my $file = $ARGV[0] or die "usage: [file] Class\nerror:no CSV filename provided on the command line\n";
my $record_class = $ARGV[1] or die "usage: [file] Class\nerror:no Record class provided on the command line\n";

$record_class = lc $record_class;
print "Record Class[$record_class]\n";

$DATADIR .= "/$record_class/";
$URIDIR .= "/$record_class/";

print "TOP DIR=$TOPDIR\n";
print "DATA DIR=$DATADIR\n";
print "URI DIR=$URIDIR\n";

system "mkdir -p $DATADIR";
#system "cp sorttable.js $TOPDIR";
system "cp gs_sortable.js $TOPDIR";
system "cp index.html $TOPDIR";
system "cp events.html $TOPDIR";
system "cp approved-gps.html $TOPDIR";
system "cp TRA-Records-Application-08.13.2016.pdf $TOPDIR";
system "cp style.css $TOPDIR";
system "cp electronics.png $TOPDIR";
#system "cp -fr jquery-ui-1.12.1.custom $TOPDIR";
#system "cp -fr jquery-ui-1.12.1 $TOPDIR";
system "cp -f gps-icon.png $TOPDIR";
my @rows;
my @row;
open(my $data, "<:encoding(utf8)", $file) or die "Could not open '$file' $!\n";

# Skip past headers (first line)
my $header = $csv->getline($data);

while (my $row = $csv->getline($data)) {

        # convert comma separated altitude to real number
        $row->[MAX_ALT] =~ tr/,//d; 

	push @rows, $row;
#	printf "$row[6]\n";
}

# sort by highest altitude first
# @rows = sort { $b->[MAX_ALT] <=> $a->[MAX_ALT] } @rows;


# trim whitespaces from leading and trailing end of URI
sub fixup_url { 
    my $i = shift;
    $i =~ s/^\s+|\s+$//g;
    return $i;
}

# remove slashes and spaces from filename string
sub cleanup_filename{
    my $filename = shift;
    # replace slashes in string
    $filename =~ s/\///g;
    # replacing spaces with -
    $filename =~ s/ /-/g; 
    # replacing comma with -
    $filename =~ s/,/-/g; 
    return $filename;
}

# download image, make mini via Image Magic

# fetch a remote file and store locally
# To save network bandwidth, if the file is the same, skip downloading
sub fetch_file{
    my $url = shift;
    my $localfile = shift;
    my $do_download = 1;

    print "\t\tAnalyzing [$url]\n";
    
    my ($type, $length, $mod) = head($url);

    unless (defined $type) { 
	print "Error: couldn't get $url\n";
	return;
    }
    print "\t\tRemote file is [", $type, "] - ", $length || "???", " bytes \n";

    # Find out when file was last modified
    if ($mod) {
	my $ago = time( ) - $mod;
	print "\t\tRemote file created [",ctime($mod),"] (",$ago," seconds) ", 
	int(.5 + $ago / (24 * 60 * 60)), " days ago\n";
    } else {
	print "\t\tI don't know when it was last modified.\n";
    }

    my $timestamp = time();
    my $lastmod = $timestamp;

    if ( -e $localfile ) {
	$timestamp = stat($localfile)->mtime;
	$lastmod = $timestamp - $mod;
    }
    else {
	$timestamp = time();
	$lastmod = $timestamp;
    }

    print "\t\tLocal file created [", ctime($timestamp), "] and ", 
    ($lastmod eq 0 ? ("unmodified\n" ): ("modified [", $lastmod, "] seconds ago\n"));

    if ($lastmod > 0) { 
	print "\t\tLocal file: $timestamp, modified [", $lastmod, "] seconds ago\n";
	getstore($url, $localfile);
	# set local file modification time to the same as that stored by the server
	utime $mod, $mod, $localfile;
    }
    else {
	print "\t\tSKIP download - File is latest\n";
    }

}

sub make_resized_images{
    my $localfile = shift;
    my $newfile = shift;
    my $geometry = shift;

    my($image, $x);

    print "\t\tNew Image[$localfile] - ";
    $image = Image::Magick->new;
    $x = $image->Read($localfile);
    warn "$x" if "$x";
    print "Resize[$geometry] ";
    $x = $image->Resize(geometry=>$geometry);
    warn "$x" if "$x";
    $x = $image->Border(width=>1, height=>1, bordercolor=>'black');
    warn "$x" if "$x";
    print "Write ...";
    $x = $image->Write($newfile);
    warn "$x" if "$x";
    print "Done\n";

}

sub make_error_images{
    my $newfile = shift;

    my($image, $x);

    print "\t\tNew Image[$newfile] - ";
    $image = Image::Magick->new;
    $image->Set(size=>'128x128');
    $x = $image->ReadImage('canvas:white');
#    $x = $image->ReadImage('alpha:transparent');
    warn "$x" if "$x";
    my $text = 'No Image';
    $image->Annotate(x=>30, y=>60, pointsize=>14, fill=>'black', text=>$text);
    $image->Border(width=>1, height=>1, bordercolor=>'black');
    print "Write ...";
    $x = $image->Write($newfile);
    warn "$x" if "$x";
    print "Done\n";
}

#
# Make 2 mini files
# 
# 
sub make_thumbnail{
    my $localfile = shift;
    my $newfile = "128x128-".$localfile;
    my $newfile2 = "160x120-".$localfile;

    $localfile = $DATADIR.$localfile;
    $newfile = $DATADIR.$newfile;
    $newfile2 = $DATADIR.$newfile2;

    make_resized_images($localfile, $newfile, '128x128');
    make_resized_images($localfile, $newfile2, '160x120');

    # if Image is > 250x250 then we need to make a web version of the image

    # else we use the same image for the web image

    # and we make a mini 128x128 icon
}

sub impulse_letter{
    my $ti = shift;

    if (looks_like_number($ti)) { 
	if ( ($ti >= 0) && ($ti < 80 )) { 
	    return "F";
	}
	if ( ($ti >= 80) && ($ti < 160 )) { 
	    return "G";
	}	
	if ( ($ti >= 160) && ($ti <= 320 )) { 
	    return "H";
	}
	elsif ( ($ti > 320) && ($ti <= 640) ) { 
	    return "I";
	}
	elsif ( ($ti > 640) && ($ti <= 1280) ) { 
	    return "J";
	}
	elsif ( ($ti > 1280) && ($ti <= 2560) ) { 
	    return "K";
	}
	elsif ( ($ti > 2560) && ($ti <= 5120) ) { 
	    return "L";
	}
	elsif ( ($ti > 5120) && ($ti <= 10240) ) { 
	    return "M";
	}
	elsif ( ($ti > 10240) && ($ti <= 20480) ) { 
	    return "N";
	}
	elsif ( ($ti > 20480) && ($ti <= 40960) ) { 
	    return "O";
	}
	elsif ( ($ti > 40960) && ($ti <= 81920) ) { 
	    return "P";
	}
	elsif ( ($ti > 81920) && ($ti <= 163840) ) { 
	    return "Q";
	}
	elsif ( ($ti > 163840) && ($ti <= 327680) ) { 
	    return "R";
	}
	elsif ( ($ti > 327680) && ($ti <= 655360) ) { 
	    return "S";
	}
	elsif ( ($ti > 655360) && ($ti <= 1310720) ) { 
	    return "T";
	}
	return "Over-T";
    }
    return "NAN";
}



sub commify {
  local $_ = shift;
  s{(?:(?<=^)|(?<=^-))(\d{4,})}
   {my $n = $1;
    $n=~s/(?<=.)(?=(?:.{3})+$)/,/g;
    $n;
   }e;
  return $_;
}

#sub commify {
#   my $input = shift;
#   $input = reverse $input;
#   $input =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
#   return reverse $input;
#}

sub print_table{ 

    print <<'DELIMETER'
	<table width="643" height="881">
	<tbody>
        <tr>
            <td colspan="2" style="height: 32px; text-align: center; background-color: #7f7f7f;"><a name="single_class">&nbsp;</a><strong><span style="font-size: 16px; color: #ffffff;">$record_class </span></strong></td>
        </tr>


DELIMETER
;
}



# --- Main --- #

# Pull down Image,GPS, and Altimeter files
# GPS, Image, and Data URL's may be separated by a comma, allowing for multiple data entries per record
for my $r (@rows) {
    $csv->combine(@$r);

    if (($r->[GPS_URL] ne "") || ($r->[IMG_URL] ne "")) { 
#	print "$header->[NAME]:";
	print "$r->[NAME]\n";

	if($r->[GPS_URL] ne "")	{
	    my @gps_urls =  split(',', $r->[GPS_URL]);
	    my $cnt = 0;
	    my $new_url = "";
	    for my $i (@gps_urls) { 

		$i = fixup_url($i);
		print "\t$header->[GPS_URL]:[$i]\n";

		my $e = $i;
                # $e has your url already

		$e =~ /.*\/(.*?)\.(.*)/;
		# split filename from url and get file extension
		my ($filename, $ext) = ($1,$2);

		# rewrite local file-name
		my $localfile = "GPS$cnt-$record_class-$r->[NAME]-$r->[TOTAL_IMPULSE]-$r->[DATE].$ext";

		$localfile = cleanup_filename($localfile);
		print "\tLocal:$DATADIR$localfile\n";
		$cnt++;

		# Save local URL
		$new_url .= $URIDIR.$localfile.",";

		# Fetch URL
		fetch_file($i, $DATADIR.$localfile);


	    }
	    # remove trailing ,
	    chop $new_url;
	    # save new URL list
	    $r->[GPS_URL] = $new_url;
	}

	if($r->[IMG_URL] ne "") {
	    my @img_urls =  split(',', $r->[IMG_URL]);
	    my $cnt = 0;
	    my $new_url = "";
	    for my $i (@img_urls) { 

		$i = fixup_url($i);
		print "\t$header->[IMG_URL]:[$i]\n";

		my $e = $i;
                # $e has your url already

		$e =~ /.*\/(.*?)\.(.*)/;
		# split filename from url and get file extension
		my ($filename, $ext) = ($1,$2);

		# hack alert - dodgy IMG url's without a filename extension become .jpg
		if ( (length $ext) > 4 ){
		    $ext = "jpg";

		    my ($type, $length, $mod) = head($i);

		    unless (defined $type) { 
			print "Error: couldn't get $i\n";
			return;
		    }
		    printf "\t\tType:$type\n";
		    my ($ct1,$ct2) = split(';', $type);

		    $ct1 =~ s/^\s+|\s+$//g ; 
		    $ct2 =~ s/^\s+|\s+$//g ; 
		    print "\t\tCT:[$ct1]+[$ct2]\n";
		    my @ct = split('/', $ct1);
		    print "\t\t\t******NOTE: guessing file extension [$ext], should be [$ct[1]] $ct2\n";

		    $ext = $ct[1];
		}

		# rewrite local file-name
		my $localfile = "IMG$cnt-$record_class-$r->[NAME]-$r->[TOTAL_IMPULSE]-$r->[DATE].$ext";

		$localfile = cleanup_filename($localfile);
		print "\tLocal:$DATADIR$localfile\n";

		$cnt++;
		# Save local URL
		$new_url .= $localfile.",";

		# Fetch URL
		fetch_file($i, $DATADIR.$localfile);
		# Make minis and web size, preserve original file for use as a download via an href link
		make_thumbnail($localfile);
	    }
	    # remove trailing ,
	    chop $new_url;
	    # save new URL list
	    $r->[IMG_URL] = $new_url;
	}
	print "----------------------------\n";
    }
}

make_error_images($TOPDIR."no-image.png");


my $outputfile = "$TOPDIR$record_class.html";

open(my $fh, '>', $outputfile) or die "Error: could not open output file[$outputfile]\n";
#print $fh "My first report generated by perl\n";
print "Outputting HTML [$outputfile]\n";

print $fh "<html lang=\"en\">\n";
print $fh "<head>\n";
print $fh "<meta charset=\"utf-8\">\n";
#print $fh "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
#print $fh "<link rel=\"stylesheet\" href=\"jquery-ui-1.12.1/jquery-ui.css\">\n";
#print $fh "<script src=\"https://code.jquery.com/jquery-1.12.1.js\"></script>\n";
#print $fh "<script src=\"jquery-ui-1.12.1/jquery-ui.js\"></script>\n";
#print $fh "<script>\n";
#print $fh "$\( function() \{\n";
#print $fh "$\( \"\#tabs\" \).tabs\(\);\n";
#print $fh "} );\n";
#print $fh "</script>\n";
#print $fh "<script src=\"sorttable.js\"></script>\n";
print $fh "<script type=\"text/javascript\" src=\"./gs_sortable.js\"></script>\n";

print $fh "<link rel=\"stylesheet\" href=\"style.css\">\n";
print $fh "</head>\n";
print $fh "<body>\n";
print $fh "<TITLE> Tripoli Records - ", ucfirst $record_class, "</TITLE>\n";
print $fh "<A HREF=\"http:\/\/www.tripoli.org/\"><IMG BORDER=0 SRC=\"http://tripoli-records.org/wp-content/uploads/2016/10/triplogo_181x90.jpg\"></A>\n";
print $fh "<H1> Altitude Records - ", ucfirst $record_class, "</H1>\n";
print $fh "<input type='button' name='action' value='By Altitude' onClick='tsDraw(\"4D\", \"records_table\"); tsDraw(\"4D\");'>  <input type='button' name='action' value='By Impulse' onClick='tsDraw(\"3D\", \"records_table\"); tsDraw(\"3D\");'>\n"; 

#print $fh "<P><FONT SIZE=2>Click on Column to sort fields</font><br>\n";
#print $fh "<table class=\"sortable\" ><tbody>\n<tr>\n";
print $fh "<table id=\"records_table\">\n<thead>\n<tr>\n";
print $fh "<th>Multimedia</th>\n";
print $fh "<th>Record $header->[CLASS]/$header->[TYPE]</th>\n";
print $fh "<th>$header->[MOTOR]</th>\n";
print $fh "<th>$header->[TOTAL_IMPULSE]</th>\n";
print $fh "<th>$header->[MAX_ALT]</th>\n";
print $fh "<th>$header->[DATE]</th>\n";
print $fh "<th>$header->[NAME]</th>\n";
print $fh "<th>Details</th>\n</tr>\n</thead>\n";

for my $r (@rows) {
    $csv->combine(@$r);
    my $cnt = 0;

    # Non complex, use first letter of the motor for class
    my $md = substr($r->[MOTOR], 0, 1);

    # Complex, use letter for total impulse
    if ($record_class eq "complex" || $record_class eq "Complex"){
	$md = impulse_letter($r->[TOTAL_IMPULSE]);
#	print("Complex-$md ($r->[TOTAL_IMPULSE])\n");
    }
    print $fh "<tr>\n";
#Class-Type-MOTOR[0] Motor Altitude Name Data [Remaining Details]w
#    print "H:$header->[CLASS]\n";

# Print out icons first
    if ($cnt eq 0) { 
	print $fh "<td width=25%>\n";
    }
    else {
	print $fh "<td>\n";
    }

    if($r->[IMG_URL] ne "") {
	my @img_urls =  split(',', $r->[IMG_URL]);
	
#	    print $fh "<div id=\"tabs\">\n";
#	    print $fh "<ul>\n";
#	    my $idx = 1;
#	    for my $i (@img_urls) { 
#		print $fh "<li><A HREF=\"#tabs-$idx\">$i</A></li>\n";
#		$idx++;
#	    }
#	    print $fh "</ul>\n";
#	    
	    #my @img_urls =  split(',', $r->[IMG_URL]);
#	    my $idx = 1;
#	    for my $i (@img_urls) { 
#		print $fh "<div id=\"tabs-$idx\"><A HREF=\"$URIDIR$i\"><IMG BORDER=0 SRC=\"", $URIDIR."128x128-".$i, "\" target=\"image_window\"></A></div>\n";
#		$idx++;
#	    }
#	    print $fh "</div>\n";


	for my $i (@img_urls) {
	    print $fh "<A HREF=\"$URIDIR$i\" target=\"new_win\"><IMG BORDER=0 SRC=\"", $URIDIR."128x128-".$i, "\"></A>"; 
	}	
    }
    else {
	print $fh "<IMG BORDER=0 SRC=\"no-image.png\">"; 
    }

    if($r->[GPS_URL] ne "")	{
	    my @gps_urls =  split(',', $r->[GPS_URL]);
	    for my $i (@gps_urls) { 
		print $fh "<A HRef=\"$i\"><IMG BORDER=0 WIDTH=32x32 SRC=\"gps-icon.png\"></A>";
	    }
    }
    else { 
    }
    print $fh "</td>\n";

# Print remaining fields
    if (($r->[CLASS] eq "Single") || ($r->[CLASS] eq "single")) { 
	print $fh "<td style=\"text-align: center;\">$r->[CLASS] Stage $md</td>\n";
    }
    else { 
	print $fh "<td style=\"text-align: center;\">$r->[CLASS]-$r->[TYPE]-$md</td>\n";
    }
    print $fh "<td style=\"text-align: center;\">$r->[MOTOR]</td>\n";
    print $fh "<td style=\"text-align: center;\">$r->[TOTAL_IMPULSE]</td>\n";
    print $fh "<td style=\"text-align: center;\">",commify($r->[MAX_ALT]),"</td>\n";
    print $fh "<td style=\"text-align: center;\">$r->[DATE]</td>\n";
    print $fh "<td style=\"text-align: center;\">$r->[NAME]</td>\n";
    print $fh "<td style=\"text-align: left;\"><FONT SIZE=-1>\n";
    if ($r->[ALTIMETERS] ne "") { 
	print $fh "Electronics:$r->[ALTIMETERS]<br>\n";
    }
    if ($r->[LOCATION] ne "") { 
	print $fh "<i>$r->[LOCATION]</i><br>\n";
    }
    if ($r->[NOTES] ne "") { 
	my $finder = URI::Find->new(sub {
	    my($uri, $orig_uri) = @_;
	    return qq|<a href="$uri">$orig_uri</a>|;
        });
	# rewrite any embedded text with URL inserted (anchored so user can click)
	$finder->find(\$r->[NOTES], \&escapeHTML);
	print $fh "$r->[NOTES] <br> <\/FONT> </td>\n";
    }

    print $fh "</tr>\n";

#    print $csv->string(), "\n";
}
print $fh "</table>\n";
print $fh "<hr>\n";
print $fh "<H6> Last updated:", ctime(time()), "</H6>\n";
print $fh "<script type=\"text/javascript\">\n";
print $fh "<!--\n";
print $fh "var TSort_Data = new Array ('records_table', '','s','','n','n','d','','');\n";
print $fh "var TSort_Initial = new Array ('3D', '4D');\n";
print $fh "tsRegister();\n";
print $fh "// -->\n</script>\n";

print $fh "</html>\n";

# close output file
close $fh;



for my $r (@rows) {
    $csv->combine(@$r);

    print $header->[NAME],  ":", $r->[NAME], "\n";
#    print $header->[MOTOR], ":", $r->[MOTOR, $header->[MAX_ALT], ":", $r->[MAX_ALT], "\n";

    if (($r->[GPS_URL] ne "") || ($r->[IMG_URL] ne "")) { 

	if($r->[GPS_URL] ne "")	{
	    my @gps_urls =  split(',', $r->[GPS_URL]);
	    for my $i (@gps_urls) { 
		print "\t$header->[GPS_URL]:[$i]\n";
	    }
	}

	if($r->[IMG_URL] ne "") {
	    my @img_urls =  split(',', $r->[IMG_URL]);
	    for my $i (@img_urls) { 
		print "\t$header->[IMG_URL]:[$i]\n";
	    }
	}
	print "----------------------------\n";
    }

#    print $csv->string(), "\n";
}

