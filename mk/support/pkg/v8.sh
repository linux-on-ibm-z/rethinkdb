if [[ "$(uname -m)" = s390x ]]; then
    # V8 3.30.33 does not support s390x.
    # This s390x-specific code can be removed once V8 is updated to 5.1+.
    version=3.28-s390

    pkg_fetch () {
        pkg_make_tmp_fetch_dir
        git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$tmp_dir/depot_tools"
        PATH="$tmp_dir/depot_tools:$PATH"
        in_dir "$tmp_dir" gclient config --unmanaged https://github.com/ibmruntimes/v8z.git
        in_dir "$tmp_dir" git clone https://github.com/ibmruntimes/v8z.git
        cd "$tmp_dir/v8z"
        git checkout 3.28-s390
        rm -rf "$src_dir"
        mv "$tmp_dir/v8z" "$src_dir"
        mv "$tmp_dir/depot_tools" "$src_dir"
        pkg_remove_tmp_fetch_dir
    }
else
    version=3.30.33.16-patched2
    # See http://omahaproxy.appspot.com/ for the current stable/beta/dev versions of v8
    src_url=http://commondatastorage.googleapis.com/chromium-browser-official/v8-${version/-patched2/}.tar.bz2
fi

pkg_install-include () {
    pkg_copy_src_to_build
# See http://omahaproxy.appspot.com/ for the current stable/beta/dev versions of v8
# See http://omahaproxy.appspot.com/ for the current stable/beta/dev versions of v8
    in_dir "$build_dir" patch -fp1 < "$pkg_dir"/patch/v8_2-HandleScope-protected.patch
    
    rm -rf "$install_dir/include"
    mkdir -p "$install_dir/include"
    if [[ "$(uname -m)" = s390x ]]; then
        # for s390x we need to generate correct header files
       cd $build_dir
       export PATH=$(pwd)/depot_tools:$PATH
       #cd v8z
       make dependencies || true
       make s390x -j4 library=static werror=no snapshot=off

       #s390x cp -RL "$src_dir/include/." "$install_dir/include"
       cp -RL "$build_dir/include/." "$install_dir/include"
       cp -RL "$build_dir/third_party/icu/source/common/." "$install_dir/include"
       sed -i.bak 's/include\///' "$install_dir/include/libplatform/libplatform.h"
    else
       cp -RL "$src_dir/include/." "$install_dir/include"
       sed -i.bak 's/include\///' "$install_dir/include/libplatform/libplatform.h"

       # -- assemble the icu headers
       if [[ "$CROSS_COMPILING" = 1 ]]; then
           ( cross_build_env; in_dir "$build_dir/third_party/icu" ./configure --prefix="$(niceabspath "$install_dir")" --enable-static "$@" )
       else
           in_dir "$build_dir/third_party/icu/source" ./configure --prefix="$(niceabspath "$install_dir")" --enable-static --disable-layout "$@"
       fi

       in_dir "$build_dir/third_party/icu/source" make install-headers-recursive

    fi
}

pkg_install () {
    pkg_copy_src_to_build
    in_dir "$build_dir" patch -fp1 < "$pkg_dir"/patch/v8_2-HandleScope-protected.patch
    sed -i.bak '/unittests/d;/cctest/d' "$build_dir/build/all.gyp" # don't build the tests
    mkdir -p "$install_dir/lib"
    if [[ "$OS" = Darwin ]]; then
        export CXXFLAGS="-stdlib=libc++ ${CXXFLAGS:-}"
        export LDFLAGS="-stdlib=libc++ -lc++ ${LDFLAGS:-}"
        export GYP_DEFINES='clang=1 mac_deployment_target=10.7'
    fi
    arch_gypflags=
    raspberry_pi_gypflags='-Darm_version=6 -Darm_fpu=vfpv2'
    host=$($CXX -dumpmachine)
    case ${host%%-*} in
        i?86)   arch=ia32 ;;
        x86_64) arch=x64 ;;
        s390x)  arch=s390x ;;
        arm*)   arch=arm; arch_gypflags=$raspberry_pi_gypflags ;;
        *)      arch=native ;;
    esac
    mode=release
    if [[ "$arch" = "s390x" ]]; then
       for lib in `find "$build_dir/out/$arch.$mode" -maxdepth 1 -name \*.a` `find "$build_dir/out/$arch.$mode/obj.target" -name \*.a` `find "$build_dir/out/$arch.$mode/obj.target/third_party/icu" -name \*.a` `find "$build_dir/out/$arch.$mode/obj.target/tools/gyp" -name \*.a` ; do
           name=`basename $lib`
           cp $lib "$install_dir/lib/${name/.$arch/}"
       done
    else
       pkg_make $arch.$mode CXX=$CXX LINK=$CXX LINK.target=$CXX GYPFLAGS="-Dwerror= $arch_gypflags" V=1
       for lib in `find "$build_dir/out/$arch.$mode" -maxdepth 1 -name \*.a` `find "$build_dir/out/$arch.$mode/obj.target" -name \*.a`; do
           name=`basename $lib`
           cp $lib "$install_dir/lib/${name/.$arch/}"
       done
       touch "$install_dir/lib/libv8.a" # Create a dummy libv8.a because the makefile looks for it
    fi

}

pkg_link-flags () {
    # These are the necessary libraries recommended by the docs:
    # https://developers.google.com/v8/get_started#hello
    for lib in libv8_{base,libbase,nosnapshot,libplatform}; do
        echo "$install_dir/lib/$lib.a"
    done
    for lib in libicu{i18n,uc,data}; do
        echo "$install_dir/lib/$lib.a"
    done
}
