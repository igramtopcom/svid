class Validators {
  Validators._();

  /// Validate URL format
  static bool isValidUrl(String url) {
    if (url.isEmpty) return false;

    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// Validate if URL is downloadable (has valid scheme and host).
  /// Accepts ANY http(s) URL — used for manual paste and download button.
  static bool isDownloadableUrl(String url) {
    if (!isValidUrl(url)) return false;

    final uri = Uri.parse(url);
    return uri.hasAuthority && uri.host.isNotEmpty;
  }

  /// Check if URL likely points to downloadable media content.
  /// Used for AUTO-PASTE only — filters out non-media URLs like Google Docs.
  /// Manual paste and download button still accept any URL via [isDownloadableUrl].
  static bool isLikelyMediaUrl(String url) {
    if (!isDownloadableUrl(url)) return false;
    final host = Uri.parse(url).host.toLowerCase();
    return _mediaDomains.any((d) => host == d || host.endsWith('.$d'));
  }

  /// Comprehensive media domain whitelist covering yt-dlp + gallery-dl supported sites.
  /// Auto-generated from 1008 yt-dlp extractors + gallery-dl extractors (1025 domains).
  /// Only used for auto-paste filtering — NOT for extraction eligibility.
  /// Manual paste and download button still accept ANY URL via [isDownloadableUrl].
  static const _mediaDomains = {
    // ── Major Platforms ──
    'youtube.com', 'youtu.be', 'youtube-nocookie.com',
    'tiktok.com', 'douyin.com',
    'instagram.com', 'threads.net',
    'facebook.com', 'fb.watch', 'fb.com',
    'twitter.com', 'x.com', 'twimg.com',
    'reddit.com', 'redd.it',
    'vimeo.com', 'vimeopro.com',
    'twitch.tv', 'twitcasting.tv',
    'kick.com',
    'linkedin.com',
    'snapchat.com',
    'pinterest.com', 'pin.it',
    // ── Video Platforms ──
    'dailymotion.com', 'dai.ly',
    'rumble.com', 'bitchute.com', 'odysee.com',
    'streamable.com', 'loom.com',
    'bilibili.com', 'bili.tv', 'b23.tv',
    'nicovideo.jp', 'nicochannel.jp', 'nico.ms',
    'vk.com', 'ok.ru', 'rutube.ru', 'plvideo.ru',
    'iqiyi.com', 'youku.com', 'tudou.com', 'mgtv.com', 'sohu.com',
    'weibo.com', 'weibo.cn', 'xiaohongshu.com',
    'acfun.cn', 'huya.com', 'douyu.com', 'kuaishou.com',
    // ── Music / Audio ──
    'soundcloud.com', 'bandcamp.com', 'mixcloud.com', 'audiomack.com',
    'audioboom.com', 'audiodraft.com', 'audius.co',
    'epidemicsound.com', 'freesound.org', 'hearthis.at',
    'last.fm', 'mixlr.com', 'musicdex.org',
    'palcomp3.com', 'player.fm', 'podbay.fm',
    'podchaser.com', 'podomatic.com',
    'qingting.fm', 'qtfm.cn', 'kuwo.cn',
    'radiko.jp', 'radiocomercial.pt', 'radiojavan.com',
    'radiokapital.pl', 'radioradicale.it', 'radiozet.pl',
    'samplefocus.com', 'soundgasm.net', 'vocaroo.com', 'voca.ro',
    'whyp.it', 'ximalaya.com',
    // ── Image / Gallery (gallery-dl) ──
    'imgur.com', 'flickr.com', 'deviantart.com',
    'pixiv.net', 'pixiv.me', 'pixivision.net',
    'artstation.com', 'behance.net',
    'imgbb.com', 'imgbox.com', 'ibb.co',
    'photobucket.com', 'fuskator.com',
    'redgifs.com', 'scrolller.com',
    'wallhaven.cc', 'wallpapercave.com',
    'issuu.com', 'speakerdeck.com',
    // ── News / Media ──
    'bbc.co.uk', 'cnn.com', 'cnbc.com',
    'foxnews.com', 'foxsports.com',
    'nytimes.com', 'washingtonpost.com', 'wsj.com',
    'bloomberg.com', 'reuters.com',
    'theguardian.com', 'dailymail.co.uk', 'mirror.co.uk',
    'huffingtonpost.com', 'businessinsider.com',
    'usatoday.com', 'bostonglobe.com',
    'hollywoodreporter.com', 'tmz.com',
    'elpais.com', 'lemonde.fr', 'lefigaro.fr',
    'corriere.it', 'gazzetta.it', 'bild.de',
    'spiegel.de', 'faz.net', 'heise.de',
    'theintercept.com', 'theepochtimes.com',
    'inc.com', 'breitbart.com',
    // ── Broadcasting / TV ──
    'cbs.com', 'cbsnews.com', 'cbssports.com', 'cc.com',
    'nbc.com', 'nbcsports.com', 'nbcolympics.com',
    'espn.com', 'espncricinfo.com',
    'abc.net.au', 'abcotvs.com',
    'hbo.com', 'cinemax.com',
    'mtv.com', 'vh1.com', 'bet.com',
    'adultswim.com', 'contv.com',
    'discovery.com', 'discoverylife.com', 'discoveryplus.com',
    'discoveryplus.in', 'discoveryplus.it',
    'animalplanet.com', 'destinationamerica.com',
    'investigationdiscovery.com', 'sciencechannel.com',
    'tlc.com', 'travelchannel.com', 'ahctv.com',
    'hgtv.com', 'cookingchanneltv.com', 'foodnetwork.com',
    'nationalgeographic.com', 'history.com', 'biography.com',
    'usanetwork.com', 'syfy.com',
    'nick.com', 'pbskids.org', 'pbs.org',
    'c-span.org', 'weather.com',
    // ── Streaming Services ──
    'curiositystream.com', 'nebula.tv',
    'hidive.com', 'tubitv.com', 'pluto.tv',
    'sonyliv.com', 'hotstar.com', 'zee5.com',
    'viu.com', 'mewatch.sg', 'iq.com',
    'magellantv.com', 'mxplayer.in',
    'playsuisse.ch', 'dropout.tv',
    'freetv.com', 'filmon.com',
    'popcorntimes.tv', 'popcorntv.it',
    'litv.tv', 'fptplay.vn',
    'ondemandchina.com', 'ondemandkorea.com',
    'rctiplus.com', 'vidio.com',
    'shemaroome.com', 'epicon.in',
    'hungama.com', 'fancode.com',
    'crunchyroll.com', 'deezer.com',
    // ── European Broadcasters ──
    'france.tv', 'francetvinfo.fr', 'franceinter.fr', 'radiofrance.fr',
    'tf1.fr', 'lcp.fr', 'lumni.fr',
    'arte.tv', 'zdf.de', '3sat.de',
    'ardmediathek.de', 'daserste.de', 'ndr.de', 'mdr.de', 'wdr.de', 'wdrmaus.de',
    'funk.net', 'kika.de', 'tagesschau.de',
    'sr-mediathek.de', 'phoenix.de', 'ran.de',
    'rtl.nl', 'rtlxl.nl', 'rtl2.de', 'rtl.lu',
    'svt.se', 'svtplay.se', 'tv4.se', 'tv4play.se', 'sverigesradio.se',
    'nrk.no', 'tv2.no',
    'dr.dk', 'dr-massive.com',
    'yle.fi', 'nelonenmedia.fi',
    'vrt.be', 'vtm.be', 'goplay.be', 'een.be', 'sporza.be',
    'rtp.pt', 'rtve.es', 'telecinco.es', 'cuatro.com', 'atresplayer.com',
    'canalsurmas.es', 'laxarxames.cat', '3cat.cat', 'crtvg.es', 'eitb.tv',
    'rai.it', 'raiplay.it', 'raiplaysound.it', 'la7.it', 'mediaset.it', 'mediaset.es',
    'sky.it', 'cielotv.it', 'leitv.it', 'tv8.it',
    'rts.ch', 'srgssr.ch',
    'orf.at', 'atv.at', 'servus.com', 'puls4.com',
    'ceskatelevize.cz', 'iprima.cz', 'nova.cz', 'seznam.cz', 'seznamzpravy.cz',
    'tvp.pl', 'tvp.info', 'tvpworld.com', 'tvn24.pl', 'go.pl', 'polskieradio.pl',
    'cda.pl', 'wp.pl', 'vod.pl',
    'rtbf.be', 'telemb.be',
    'lrt.lt', 'lsm.lv', 'err.ee', 'duoplay.ee',
    'nova.rs', 'nova.bg', 'btvplus.bg',
    'rtvslo.si', 'hrt.hr',
    'markiza.sk', 'joj.sk',
    'tv2play.hu', 'sztv.hu',
    'rte.ie', 'itv.com', 'stv.tv',
    's4c.cymru', 'tvplayer.com',
    'bfi.org.uk', 'learningonscreen.ac.uk',
    // ── Asian Broadcasters ──
    'nhk.or.jp', 'ntv.co.jp', 'tbs.co.jp', 'fujitv.co.jp',
    'abema.tv', 'tver.jp',
    'naver.com', 'kakao.com', 'nate.com',
    'jtbc.co.kr', 'sbs.co.kr', 'mbn.co.kr', 'sooplive.co.kr', 'flextv.co.kr',
    'cts.com.tw', 'nexttv.com.tw', 'appledaily.com.tw',
    'vtv.vn', 'kenh14.vn', 'mocha.com.vn',
    'cnnindonesia.com', 'liputan6.com', 'kompas.com',
    'gmanetwork.com',
    'ndtv.com',
    // ── Russian / CIS Platforms ──
    '1tv.ru', '5-tv.ru', 'ntv.ru', 'ren.tv',
    'gazeta.ru', 'lenta.ru', 'tass.ru', 'itar-tass.com',
    'rt.com', 'ruptly.tv',
    'smotrim.ru', 'vgtrk.com', 'tvc.ru', 'mir24.tv',
    'ivi.ru', 'more.tv', 'nuum.ru',
    'tvigle.ru', 'videomore.ru',
    'krasview.ru', 'goodgame.ru',
    'kinopoisk.ru', 'yandex.ru', 'dzen.ru', 'zen.yandex.ru',
    'mail.ru', 'getcourse.ru',
    'boosty.to',
    'ruv.is',
    'aitube.kz',
    // ── Middle East / Africa ──
    'telewebion.com', 'aparat.com',
    'manototv.com', 'roya.tv',
    'islamchannel.tv', 'fuyin.tv',
    'skynewsarabia.com',
    'karaoketv.co.il', 'maariv.co.il', 'sport5.co.il', 'walla.co.il',
    '2m.ma',
    // ── Latin America ──
    'globo.com', 'r7.com', 'uol.com.br',
    'eltrecetv.com.ar',
    'canal1.com.co', 'caracoltv.com', 'rtvcplay.co', 'senalcolombia.tv', 'winsports.co',
    't13.cl', 'biobiochile.cl',
    // ── Canada / Australia / NZ ──
    'cbc.ca', 'cp24.com', 'tou.tv',
    'telequebec.tv', 'tfo.org', 'tvaplus.ca',
    '9now.com.au', '9news.com.au', '7plus.com.au',
    'sbs.com.au', 'rtrfm.com.au', 'skynews.com.au',
    'nzherald.co.nz', 'nzonscreen.com', 'news.co.nz',
    // ── Education / Knowledge ──
    'ted.com', 'academicearth.org',
    'udemy.com', 'pluralsight.com', 'lynda.com',
    'frontendmasters.com', 'egghead.io', 'laracasts.com',
    'teamtreehouse.com', 'platzi.com',
    'raywenderlich.com', 'packtpub.com',
    'lecturio.com', 'lecturio.de',
    'safaribooksonline.com', 'cybrary.it', 'itpro.tv',
    'kth.se', 'su.se', 'tum.de', 'tum.live',
    'uni-hamburg.de', 'u-strasbg.fr', 'tugraz.at',
    'videolectures.net', 'slideslive.com',
    'brilliantpala.org', 'ocwconsortium.org',
    'pyvideo.org', 'infoq.com',
    'gdcvault.com', 'gputechconf.com',
    'nobelprize.org', 'teachertube.com', 'teachingchannel.org',
    'scte.org',
    // ── Sports ──
    'nfl.com', 'nba.com', 'mlb.com', 'nrl.com',
    'fifa.com', 'olympics.com',
    'formula1.com', 'motorsport.com',
    'europeantour.com', 'pgatour.com',
    'masters.com', 'wimbledon.com', 'tennistv.com',
    'bundesliga.com', 'dfb.de',
    'sportdeutschland.tv',
    '247sports.com', 'bleacherreport.com',
    'footyroom.com', 'nfhsnetwork.com',
    // ── Gaming ──
    'steamcommunity.com', 'steampowered.com',
    'gamejolt.com', 'gamespot.com', 'giantbomb.com',
    'ign.com', 'metacritic.com',
    'rockstargames.com', 'nintendo.com', 'hytale.com',
    'gameclips.io', 'xboxclips.com', 'medal.tv',
    'gronkh.tv', 'dlive.tv', 'loco.com',
    'openrec.tv', 'mirrativ.com', 'showroom-live.com',
    'vimm.tv', 'picarto.tv', 'caffeine.tv',
    '3speak.tv',
    // ── Podcasts ──
    'anchor.fm', 'simplecast.com', 'libsyn.com',
    'megaphone.fm', 'iheart.com',
    'acast.com', 'listennotes.com',
    'thisamericanlife.org', 'ridehome.info',
    'npr.org', 'prankcast.com',
    // ── Creative / Arts ──
    'newgrounds.com', 'itch.io',
    'musescore.com', 'piapro.jp',
    'monstercat.com', 'hypergryph.com',
    'nekohacker.com', 'stacommu.jp',
    'hitrecord.org', 'cultureunplugged.com',
    'shortfilm.de',
    // ── Social / Community ──
    'tumblr.com', 'substack.com',
    'coub.com', '9gag.com',
    'gab.com', 'parler.com', 'truthsocial.com',
    'kooapp.com', 'likee.video',
    'triller.co', 'viddler.com',
    'vidlii.com', 'myspace.com',
    'livejournal.com', 'blogger.com',
    'wykop.pl', 'plurk.com',
    'crowdbunker.com', 'rokfin.com',
    'younow.com', 'whowatch.tv',
    // ── Cloud Storage / Tools ──
    'drive.google.com', 'dropbox.com', 'box.com',
    'microsoftstream.com',
    'webex.com',
    'bbcollab.com', 'adobeconnect.com',
    'clipchamp.com', 'screencast.com', 'screencast-o-matic.com', 'screenrec.com',
    'gofile.io', 'yadi.sk',
    // ── Misc Media Platforms ──
    'archive.org', 'wikimedia.org',
    'imdb.com',
    'vevo.com', 'yahoo.com', 'yahoo.co.jp',
    'msn.com', 'rottentomatoes.com',
    'reverbnation.com', 'hotnewhiphop.com',
    'genius.com', 'discogs.com', 'beatport.com',
    'brightcove.com', 'brightcove.net', 'kaltura.com',
    'theplatform.com', 'embedly.com',
    'aeon.co', 'nowness.com',
    'gopro.com', 'redbull.com',
    'startrek.com',
    'thisoldhouse.com', 'dw.com',
    // ── Regional / Niche ──
    'dagbladet.no', 'bt.no', 'kommunetv.no', 'p3.no',
    'aftonbladet.se', 'moviezine.se',
    'nzz.ch', 'canalalpha.ch', 'telebaern.tv', 'telem1.ch', 'telezueri.ch', 'tvo-online.ch',
    '20min.ch', '24syv.dk', '24tv.ua',
    'telegraaf.nl', 'nos.nl', 'schooltv.nl', 'npo.nl', 'omroepwnl.nl', 'dumpert.nl', 'tweakers.net',
    'tv5monde.com', 'tv5unis.ca',
    'allocine.fr', 'philharmoniedeparis.fr',
    'cinetecamilano.it', 'internazionale.it', 'ilpost.it', 'amica.it',
    'iltalehti.fi', 'mtvuutiset.fi',
    'ertflix.gr', 'ant1news.gr',
    'hkedcity.net', 'nextmedia.com',
    'apa.at', 'bibeltv.de', 'tele5.de', 'tele-task.de',
    'n-tv.de', 'n-joy.de', 't-online.de',
    'galileo.tv', 'gaskrank.tv', 'massengeschmack.tv', 'muenchen.tv',
    'oktoberfest-tv.de', 'rheinmaintv.de', 'advopedia.de', 'germanupa.de',
    'moviepilot.de', 'myspass.de', 'netzkino.de', 'universal-music.de',
    'toggo.de', 'hse.de', 'magentamusik.de',
    'rozhlas.cz', 'mujrozhlas.cz', 'tvnoe.cz', 'aktualne.cz',
    'tokfm.pl', 'webcamera.pl', 'swipeto.pl',
    'tvszombathely.hu',
    'trtcocuk.net.tr', 'trtworld.com', 'startv.com.tr', 'turkiye.com.tr',
    'noz.de', 'holodex.net',
    'zetland.dk', 'restudy.dk', 'ft.dk', 'tv2bornholm.dk',
    'lnk.lt',
    'indavideo.hu', 'mojevideo.sk', 'mojvideo.com',
    'myvideo.ge', 'izlesene.com',
    'ivideon.com',
    // ── Short-URL / Redirect Domains ──
    'bit.ly', 'ow.ly', 'buff.ly', 'dlvr.it',
    't.co', 'href.li', 'vid.ly', 'amzn.to',
    'livestre.am',
    // ── Misc yt-dlp / gallery-dl supported ──
    '163.com', 'qq.com', 'baidu.com', 'taptap.cn', 'taptap.io',
    'zhihu.com', 'kankanews.com', 'weiqitv.com',
    'toutiao.com', 'ixigua.com', 'pearvideo.com',
    'meipai.com', 'huajiao.com', 'livr.jp',
    'asobistore.jp', 'skeb.jp', 'voicy.jp',
    '56.com', 'ku6.com', 'le.com', 'letv.com', 'pps.tv',
    '8tracks.com', '17.live',
    'afreecatv.com', 'bigo.tv', 'chilloutzone.net',
    'clippituser.tv', 'closertotruth.com',
    'colbertlateshow.com', 'clyp.it',
    'daxab.com', 'duboku.io',
    'ebaumsworld.com',
    'fc-zenit.ru', 'fathom.video',
    'fem.com', 'bigflix.com',
    'historicfilms.com', 'snotr.com',
    'teamcoco.com', 'webofstories.com',
    'thestar.com', 'ustream.tv', 'ustudio.com',
    'vbox7.com', 'vids.io',
    'videodetective.com', 'videofy.me', 'videoken.com',
    'minoto-video.com', 'viidea.com', 'viidea.net',
    'viqeo.tv', 'vuclip.com',
    'wevidi.net', 'weyyak.com',
    'xinpianchang.com', 'yappy.media',
    'alura.com.br', 'amadeus.tv', 'amara.org',
    'angel.com', 'animationdigitalnetwork.com',
    'altcensored.com', 'alsace20.tv', 'air.tv',
    'allstar.gg', 'axs.tv',
    'backscreen.com', 'banbye.com', 'banned.video',
    'beacon.tv', 'behindkink.com',
    'boxcast.tv', 'bpb.de',
    'byutv.org', 'callin.com',
    'camdemy.com', 'camfm.co.uk',
    'dctp.tv', 'democracynow.org',
    'digitalconcerthall.com', 'digiteka.net',
    'drtalks.com',
    'eggs.mu',
    'eyedo.tv',
    'floatplane.com',
    'freespeech.org',
    'harpodeon.com',
    'hypem.com', 'iwara.tv',
    'jamendo.com', 'jeuxvideo.com', 'jove.com',
    'kickstarter.com',
    'mychannels.video', 'myvidster.com', 'mzaalo.com',
    'ncpa-classic.com', 'nerdcubed.co.uk',
    'netverse.id', 'ninaprotocol.com',
    'nts.live', 'oneplace.com',
    'ora.tv', 'outsidetv.com',
    'parliamentlive.tv', 'parti.com', 'patreon.com',
    'peer.tv',
    'piramide.tv', 'planetmarathi.com',
    'pokergo.com', 'pr0gramm.com',
    'projectveritas.com', 'puhutv.com',
    'q-dance.com', 'rad.io', 'rad.live',
    'radio1.be', 'recode.net',
    'roosterteeth.com', 'rudo.video',
    'saitosan.net', 'sauceplus.com',
    'sen.com', 'sendtonews.com',
    'shiey.com', 'skylinewebcams.com',
    'softwhiteunderbelly.com', 'sovietscloset.com',
    'springboardplatform.com', 'stage-plus.com',
    'streetvoice.com', 'subsplash.com',
    'swearnet.com',
    'the-hole.tv', 'thehighwire.com',
    'trunews.com', 'ttinglive.com',
    'tvw.org', 'twentythree.net', '23video.com',
    'ukcolumn.org', 'ulizaportal.jp', 'uliza.jp', 'ultimedia.com',
    'un.org', 'unsafespeech.com',
    'uplynk.com', 'vod-platform.net',
    'webcaster.pro', 'weverse.io',
    'x-minus.org',
    'audi-mediacenter.com', 'atscaleconference.com',
    'clubdam.com', 'clubic.com',
    'dplay.com', 'dplay.co.uk',
    'israelnationalnews.com',
    'maoritelevision.com', 'medici.tv',
    'noonscreen.com', 'onefootball.com', 'onepeloton.com',
    'onionstudios.com', 'onsen.ag',
    'paramountpressexpress.com',
    'playvids.com', 'playwire.com',
    'rinse.fm', 'slideshare.net',
    'top.tv', 'traileraddict.com',
    'wwe.com', 'zaiko.io',
    'are.na', 'lofter.com', 'mangoxo.com', 'telegra.ph',
    // ── NSFW (yt-dlp supported) ──
    'xvideos.com', 'xvideos.es',
    'cam4.com', 'cammodels.com', 'camsoda.com',
    'stripchat.com', 'manyvids.com',
    'eporner.com', 'redtube.com',
    '4tube.com', 'tube8.com',
    'youjizz.com', 'youporn.com',
    'fux.com', 'pornflip.com', 'porntube.com',
    'pornbox.com', 'pornerbros.com', 'pornotube.com',
    'pornovoisines.com', 'pornoxo.com', 'porntop.com',
    'nuvid.com', 'spankbang.com', 'sunporno.com',
    'slutload.com', 'sexu.com', 'thisvid.com',
    'alphaporno.com', 'drtuber.com', 'erocast.me', 'eroprofile.com',
    'lovehomeporn.com', 'motherless.com', 'noodlemagazine.com',
    'nonktube.com', 'peekvids.com', 'rule34video.com', 'zenporn.com',
    'xxxymovies.com',
  };

  /// Validate file path
  static bool isValidPath(String path) {
    if (path.isEmpty) return false;

    // Basic path validation - can be extended based on platform
    return !path.contains(RegExp(r'[<>"|?*]'));
  }

  /// Validate if number is within range
  static bool isInRange(num value, num min, num max) {
    return value >= min && value <= max;
  }

  /// Validate email format (basic validation)
  static bool isValidEmail(String email) {
    if (email.isEmpty) return false;

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    return emailRegex.hasMatch(email);
  }

  /// Validate if string is not empty
  static bool isNotEmpty(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  /// Validate minimum length
  static bool hasMinLength(String value, int minLength) {
    return value.length >= minLength;
  }

  /// Validate maximum length
  static bool hasMaxLength(String value, int maxLength) {
    return value.length <= maxLength;
  }

  /// Validate if value is a valid port number
  static bool isValidPort(int port) {
    return isInRange(port, 1, 65535);
  }

  /// Validate if value is a positive number
  static bool isPositive(num value) {
    return value > 0;
  }

  /// Validate if value is non-negative
  static bool isNonNegative(num value) {
    return value >= 0;
  }
}
