# LibPawn

Portable arithmetic (Universal, XPosit, PAWN).

For documentation and usage, see the comments in the include-header or `examples/`.

## Building the Library

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
# run tests
./build/test/test_pawn
```

## Memory Checking

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_FLAGS="-g -O0 -fsanitize=address -fno-omit-frame-pointer" -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address"
cmake --build build
./build/test/test_pawn
```

## Build and run Examples

```bash
cd examples
make
./basic_usage.elf # or any other program
```

## Writing Your Own Programs

Build library first:

```bash
cmake -B build
cmake --build build
```

### Static Linking (Recommended)

```bash
g++ -I[path/to/libpawn/include] -o my_program my_program.cpp [path/to/libpawn/build/libpawn_static.a]
```

### Dynamic Linking

```bash
g++ -I[path/to/libpawn/include] -o my_program my_program.cpp -L[path/to/libpawn/build] -lpawn -Wl,-rpath,[path/to/libpawn/build]
```
