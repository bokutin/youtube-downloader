#!/usr/bin/env perl

use strict;
use warnings;

use CGI::Util qw(unescape);
use FLV::ToMP3;
use FindBin;
use Getopt::Long;
use IO::All;
use JSON;
use WWW::Mechanize;
use Web::Scraper;

#use Data::Dumper;
#use YAML::Syck;
#$YAML::Syck::ImplicitUnicode = 1;

binmode(STDOUT, ":utf8");

my $mech = WWW::Mechanize->new( cookie_jar => {} );
$mech->agent_alias( 'Windows IE 6' );
#$mech->proxy(['http'], 'http://localhost:8080/');

#use MIME::Types;
#sub _extension {
#    my ( $type ) = @_;
#
#    my ($first) = MIME::Types::by_mediatype($type);
#    $first->[0];
#}

sub _flv_res {
    my ( @uris ) = @_;

    for (@uris) {
        eval {
            $mech->add_header( Referer => undef );
            $mech->get($_);
        };

        if ($@) {
            next;
        }
        else {
            return $mech->res;
        }
    }

    return undef;
}

sub _flv_res_fake {
    my $rc = 200;
    my $msg = "OK";
    my $header = [
        'Cache-Control'       => 'public,max-age=3600',
        'Date'                => 'Sat, 12 Dec 2009 16:49:12 GMT',
        'Transfer-Encoding'   => 'chunked',
        'Via'                 => '1.1 foil.local (HTTP::Proxy/0.24)',
        'Server'              => 'gvs 1.0',
        'Content-Length'      => '8123134',
        'Content-Type'        => 'video/x-flv',
        'Expires'             => 'Sat, 12 Dec 2009 17:49:12 GMT',
        'Last-Modified'       => 'Tue, 14 Oct 2008 10:44:58 GMT',
        'Content-Disposition' => 'attachment; filename="video.flv"',
    ];
    my $content = "x" x 8123134;
    HTTP::Response->new($rc, $msg, $header, $content);
}

sub _flv2mp3 {
    my ( $filename ) = @_;

    my $flv_filename = $filename;
    my $mp3_filename = do {
        my $fn = $flv_filename;
        $fn =~ s/\.[^\.]*$/.mp3/;
        $fn;
    };

    my $converter = FLV::ToMP3->new();
    $converter->parse_flv($flv_filename);
    $converter->save($mp3_filename);

    $mp3_filename;
}

sub _usage {
    <<"USAGE";

usage:
    $0 --user USER_ID

ex:
    http://www.youtube.com/watch?v=ABCDEFGHIJK
    $0 --user ABCDEFGHIJK

USAGE
}

sub _video_fragment {
    my ( $user, $page ) = @_;

    my $url = qq{http://www.youtube.com/profile?action_ajax=1&user=$user&new=1&box_method=load_playlist_page&box_name=user_playlist_navigator};
    my $messages = qq|[{"type":"box_method","request":{"name":"user_playlist_navigator","x_position":1,"y_position":-1,"palette":"default","method":"load_playlist_page","params":{"playlist_name":"uploads","encrypted_playlist_id":"uploads","query":"","encrypted_shmoovie_id":"uploads","page_num":$page,"view":"play","playlist_sort":"default"}}}]|;

    $mech->post($url, { messages => $messages });

    my $json_text = $mech->content;
    $json_text =~ s/^while\(1\);//;
    my $perl_scalar = from_json($json_text);
    $perl_scalar;
}

sub _video_fragment2videos {
    my ( $data ) = @_;

# [[[
#        <div id="playnav-video-play-uploads-35-JxBj_3nRkhI" class="playnav-item playnav-video">
#                <div style="display:none" class="encryptedVideoId">JxBj_3nRkhI</div>
#
#                <div id="playnav-video-play-uploads-35-JxBj_3nRkhI-selector" class="selector"></div>
#                <div class="content">
#                        <div class="playnav-video-thumb link-as-border-color">
#                                <a class="video-thumb-90 no-quicklist" href="/watch?v=JxBj_3nRkhI" onclick="playnav.playVideo('uploads','35','JxBj_3nRkhI');return false;"  ><img title="ピアノ演奏　『美女と野獣』　BEAUTY AND THE BEAST"    src="http://i3.ytimg.com/vi/JxBj_3nRkhI/default.jpg" class="vimg90 yt-uix-hovercard-target"  alt="ピアノ演奏　『美女と野獣』　BEAUTY AND THE BEAST"></a>
#
#                        </div>
#                        <div class="playnav-video-info">
#                                <a href="/watch?v=JxBj_3nRkhI" class="playnav-item-title ellipsis" onclick="playnav.playVideo('uploads','35','JxBj_3nRkhI');return false;" id="playnav-video-title-play-uploads-35-JxBj_3nRkhI"><span >ピアノ演奏　『美女と野獣』　BEAUTY AND THE BEAST</span></a>
#
#                                <div class="metadata">
#
#
#
#
#
#
#                                                再生回数 176,610 回  -  2 年前
#
#
#
#
#                                </div>
#
#                                <div style="display:none" id="playnav-video-play-uploads-35">JxBj_3nRkhI</div>
#                        </div>
#                </div>
#        </div> at list.pl line 67.
# ]]]
    my $videos = scraper {
        process ".playnav-item", "videos[]" => scraper {
            process ".encryptedVideoId",            id    => 'TEXT';
            process ".playnav-video-info a",        link  => '@href';
            process ".playnav-video-info a",        title => 'TEXT';
            process ".playnav-video-info metadata", meta  => 'TEXT';
        };
    };

    #- 
    #  id: RURnITMQugM
    #  link: /watch?v=RURnITMQugM
    #  title: ピアノ演奏　～　風の谷のナウシカ　～　『風の伝説』
    #  meta: 再生回数 176,610 回  -  2 年前
    $videos->scrape( $data )->{videos};
}


sub _videoplayback_uris {
    my ( $html ) = @_;

    $html =~ m/'SWF_ARGS': ({.*?})/ or die;
    my $arg = from_json($1);
    my $val = unescape($arg->{fmt_url_map});
    my ($unknow, @urls) = split(/\|/, $val);
    @urls;
}

sub _videos {
    my ( $user ) = @_;

    my $page = 0;
    my @videos;
    PAGES: while (1) {
        for my $result (@{_video_fragment($user, $page)}) {
            my $lists = _video_fragment2videos($result->{data}) || [];
            if ( @$lists == 0 ) {
                last PAGES;
            }
            else {
                push @videos, @$lists;
                $page++;
                next;
            }
        }
    }

    @videos;
}

sub _videos_fake {
    +{
        id    => 'RURnITMQugM',
        link  => '/watch?v=RURnITMQugM',
        title => 'ピアノ演奏　～　風の谷のナウシカ　～　『風の伝説』',
    };
}

sub _watch_uri {
    my ( $path ) = @_;

    my $uri = URI->new("http://www.youtube.com");
    $uri->path($path);
    $uri;
}

main: {
    my $user;

    args_check: {
        my $ret = GetOptions(
            "user=s" => \$user,
        );
        unless ($user) {
            print _usage();
            exit -1;
        }
    }

    my @videos = _videos($user);
    #my @videos = _videos_fake;

    for (@videos) {
        my $basename  = $_->{title} || $_->{id};
        #my $extension = _extension( $flv_res->headers->content_type );
        my $extension = "flv";
        my $filename  = join(".", $basename, $extension);

        if (-f $filename) {
            printf("%s exists. skipping...\n", $filename);
            next;
        }

        my $watch_uri = _watch_uri($_->{link});
        $mech->get($watch_uri);
        my $html = $mech->content;
        #io->file("$FindBin::Bin/../tmp/html") < $html;

        my @videoplayback_uris = _videoplayback_uris($html);
        my $flv_res = _flv_res(@videoplayback_uris);
        #my $flv_res = _flv_res_fake(@videoplayback_uris);

        unless ($flv_res) {
            printf("%s error occured. skipping...\n", $filename);
            next;
        }

        save: {
            io->file($filename)->binary->print($flv_res->content)->close;
            my $mp3_filename = _flv2mp3($filename);

            my $mtime = $flv_res->headers->last_modified;
            for ($filename, $mp3_filename) {
                io->file($_)->utime($mtime, $mtime);
            }

            printf("%s saved.\n", $filename);
        };
    }
}

# vim: set foldmaker=[[[,]]] :
