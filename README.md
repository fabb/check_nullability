# Introduction

This script checks Objective-C headers for nullability annotations.

Motivation is that in a mixed Objective-C/Swift Xcode project, all headers without nullability annotations are imported as `Implicitly Unwrapped Optionals`. That might lead to runtime crashes in case one forgets to use safe unwraps or checks.

With this script, all headers that do not contain any nullability annotations can be found. The compiler does the rest: if a header contains at least one nullability annotation, the compiler will output warnings for all other pointers in that file that miss one. Combine it with `Treat Warnings as Errors` for best results.

Usually one does not want to check all headers, but only the ones imported via the `bridging header`, so this script provides an option to support this.

For a more detailed problem and solution description, I wrote [this blog post](http://tech.willhaben.at/2016/12/avoiding-implicit.html).

# Dependencies

The script depends on `ruby 2.0.0` or higher and does not have any external dependencies. This ruby version is installed by default on OSX El Capitan or macOS Sierra.

# Running

To display all the possible options, use the `-h` flag:

```
./check_nullability.rb -h
```

The script can be run without any options in order to check all `.h` files in the current directory and all subdirectories:

```
./check_nullability.rb
```

However, it is more useful – or _realistic_ for big existing projects – to only check `#imports` of the `bridging header` (and their recursive imports accordingly):

```
./check_nullability.rb -s Source/SupportingFiles/MyProject-Bridging-Header.h
```

In order to specify which paths should be searched, include and exclude paths can be provided. Multiple paths can be provided by separating them with `,`:

```
./check_nullability.rb -s Source/SupportingFiles/MyProject-Bridging-Header.h -i Source -e Source/External,Source/Generated
```

# Integrate with Xcode

In order to run the script with every build, and thus make sure no imports missing nullability annotations are added to the bridging header in the future, just add a [build phase](https://www.objc.io/issues/6-build-tools/build-process/#build-phases) which executes this script.

Be sure to insert the build phase **before** the `Compile Sources` build phase. That way the build will be aborted early if nullability is missing, and not recompile the whole project first.

The script generates an error per header file that misses nullability annotations. All errors will show up in the Xcode issue navigator, where one can conveniently jump to the according file.

If you want to run the script without aborting the build on error (not recommended), there is the `-w` flag. It will generate warnings instead, and not fail the build.

As this script only checks each header for having at least ONE nullability annotation, we rely on the support of the compiler. Clang will warn by default about each missing nullability annotation in a header, but only if the header contains at least one nullability annotation. It's a bit weird, but probably Apple wanted to avoid outputting a lot of warnings for legacy projects. Either way, to make that even safer, I'd suggest to also activate `GCC_TREAT_WARNINGS_AS_ERRORS`, so nothing can slip through.

There might be header files that contain no pointers at all (e.g. headers only containing enum declarations). In order to satisfy the script, one has to add the `NS_ASSUME_NONNULL_BEGIN/END` macros anywhere in the file:

```
NS_ASSUME_NONNULL_BEGIN
NS_ASSUME_NONNULL_END

// some declarations without pointers
```

# Contributions

You are invited to make a PR to improve this script. Note that I have limited time to support this project, so please no codestyle-only PRs.

# License

MIT License see [LICENSE.md](LICENSE.md).
