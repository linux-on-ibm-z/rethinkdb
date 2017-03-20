
version=3.2.0

src_url=https://github.com/google/protobuf/archive/v$version.tar.gz
src_url_sha1=2d47c98c7f35d74d475ba0796d345a45c22030fd

pkg_install-include () {
    in_dir "$src_dir/src" find . -name \*.h | while read -r file; do
        mkdir -p "$install_dir/include/$(dirname "$file")"
        cp -af "$src_dir/src/$file" "$install_dir/include/$file"
    done
}

pkg_install () (
    pkg_copy_src_to_build

    configure_flags="--libdir=${install_dir}/lib"

    if [[ "$CROSS_COMPILING" = 1 ]]; then
        cross_build_dir=$build_dir/cross_build
        configure_flags="--with-protoc=$cross_build_dir/src/protoc --host=$($CXX -dumpmachine)"
        if ! test -e $cross_build_dir/src/protoc; then
            cp -a "$src_dir/." "$cross_build_dir"
            (
                cross_build_env
                in_dir "$cross_build_dir" ./configure --enable-static --disable-shared
                in_dir "$cross_build_dir" make
            )
        fi
    fi

    in_dir "$build_dir" ./autogen.sh
    pkg_configure --prefix="$(niceabspath "$install_dir")" $configure_flags --enable-static --disable-shared
    pkg_make ${protobuf_install_target:-install}

    if [[ "$CROSS_COMPILING" = 1 ]]; then
        cp -f $cross_build_dir/src/protoc $install_dir/bin/protoc
    fi
)

pkg_install-windows () {
    pkg_copy_src_to_build

    for project in libprotobuf libprotoc protoc; do
        in_dir "$build_dir" "$MSBUILD" /nologo /maxcpucount /p:Configuration=$CONFIGURATION /p:Platform=$PLATFORM vsprojects\\$project.vcxproj
    done

    cp "$build_dir/vsprojects/$VS_OUTPUT_DIR/libprotobuf.lib" "$windows_deps_libs/"
    mkdir -p "$install_dir/bin"
    cp "$build_dir/vsprojects/$VS_OUTPUT_DIR/protoc.exe" "$install_dir/bin/"
}
