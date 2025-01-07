{
  lib,
  stdenv,
  fetchzip,
  gperf,
  pkg-config,
  boost,
  libevent,
  libuuid,
  wolfssl,
  libmemcached,
  postgresql,
  sqlite,
  tokyocabinet,
}:

stdenv.mkDerivation rec {
  pname = "gearmand";
  version = "1.1.21";

  src = fetchzip {
    url = "https://github.com/gearman/gearmand/releases/download/${version}/gearmand-${version}.tar.gz";
    hash = "sha256-ClzhEhx69bwblJ+jL0rsBprZIKm9XCnGg//3AYr5lIc=";
  };

  configureFlags = [ "--with-boost-libdir=${boost.out}/lib" ];

  nativeBuildInputs = [
    gperf
    pkg-config
  ];

  buildInputs = [
    boost
    libevent
    libuuid
    wolfssl
    libmemcached
    postgresql
    sqlite
    tokyocabinet
  ];

  meta = with lib; {
    description = "Generic application framework to farm out work to other machines or processes that are better suited to do the work";
    homepage = "http://gearman.org/";
    changelog = "https://github.com/gearman/gearmand/blob/${version}/ChangeLog";
    license = licenses.bsd3;
    maintainers = with maintainers; [ erictapen ];
    mainProgram = "gearmand";
    platforms = platforms.linux;
  };
}
