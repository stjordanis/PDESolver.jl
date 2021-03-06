# Input/Output

```@meta
  CurrentModule = Utils
```


The functions and types defined here facilitate writing to `STDOUT` and
`STDERR` as well as files.
In particular, performance tests have shown that buffering is important
when running in parallel.
To this end, the [`BufferedIO`](@ref) type is introduced that stores output in
an in-memory buffer before writing to an underlying stream.
This can create some difficulty when debuging, because output written to
a buffered stream is not immediately written to the underlying stream.
In cases where precise control of output is needed, users should call
[`flush`](@ref) to make sure all output is written to the underlying stream

## Detailed Documentation

```@autodocs
  Modules = [Utils]
  Pages = ["Utils/io.jl"]
```
