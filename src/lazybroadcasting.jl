struct LazyArrayStyle{N} <: AbstractArrayStyle{N} end
LazyArrayStyle(::Val{N}) where N = LazyArrayStyle{N}()
LazyArrayStyle{M}(::Val{N}) where {N,M} = LazyArrayStyle{N}()


struct BroadcastArray{T, N, BRD<:Broadcasted} <: AbstractArray{T, N}
    broadcasted::BRD
end

BroadcastArray{T,N}(bc::BRD) where {T,N,BRD<:Broadcasted} = BroadcastArray{T,N,BRD}(bc)
BroadcastArray{T}(bc::Broadcasted{<:Union{Nothing,BroadcastStyle},<:Tuple{Vararg{Any,N}},<:Any,<:Tuple}) where {T,N} =
    BroadcastArray{T,N}(bc)

_broadcast2broadcastarray(a, b...) = tuple(a, b...)
_broadcast2broadcastarray(a::Broadcasted, b...) = tuple(BroadcastArray(a), b...)

_BroadcastArray(bc::Broadcasted) = BroadcastArray{combine_eltypes(bc.f, bc.args)}(bc)
BroadcastArray(bc::Broadcasted{S}) where S =
    _BroadcastArray(instantiate(Broadcasted{S}(bc.f, _broadcast2broadcastarray(bc.args...))))
BroadcastArray(b::BroadcastArray) = b
BroadcastArray(f, A, As...) = BroadcastArray(broadcasted(f, A, As...))

axes(A::BroadcastArray) = axes(A.broadcasted)
size(A::BroadcastArray) = map(length, axes(A))

IndexStyle(::BroadcastArray{<:Any,1}) = IndexLinear()

@propagate_inbounds getindex(A::BroadcastArray, kj::Int...) = A.broadcasted[kj...]


@propagate_inbounds _broadcast_getindex_range(A::Union{Ref,AbstractArray{<:Any,0},Number}, I) = A[] # Scalar-likes can just ignore all indices
# Everything else falls back to dynamically dropping broadcasted indices based upon its axes
@propagate_inbounds _broadcast_getindex_range(A, I) = A[I]

getindex(B::BroadcastArray{<:Any,1}, kr::AbstractVector{<:Integer}) =
    BroadcastArray(B.broadcasted.f, map(a -> _broadcast_getindex_range(a,kr), B.broadcasted.args)...)

copy(bc::Broadcasted{<:LazyArrayStyle}) = BroadcastArray(bc)

# issue 16: sum(b, dims=(1,2,3)) faster than sum(b)
Base._sum(b::BroadcastArray{T,N}, ::Colon) where {T,N} = first(Base._sum(b, ntuple(identity, N)))
Base._prod(b::BroadcastArray{T,N}, ::Colon) where {T,N} = first(Base._prod(b, ntuple(identity, N)))

BroadcastStyle(::Type{<:BroadcastArray{<:Any,N}}) where N = LazyArrayStyle{N}()
BroadcastStyle(L::LazyArrayStyle{N}, ::StaticArrayStyle{N}) where N = L
BroadcastStyle(::StaticArrayStyle{N}, L::LazyArrayStyle{N})  where N = L

"""
    BroadcastLayout(f, layouts)

is returned by `MemoryLayout(A)` if a matrix `A` is a `BroadcastArray`.
`f` is a function that broadcast operation is applied and `layouts` is
a tuple of `MemoryLayout` of the broadcasted arguments.
"""
struct BroadcastLayout{F, LAY} <: MemoryLayout
    f::F
    layouts::LAY
end

MemoryLayout(A::BroadcastArray) = BroadcastLayout(A.broadcasted.f, MemoryLayout.(A.broadcasted.args))

## scalar-range broadcast operations ##
# Ranges already support smart broadcasting
for op in (+, -, big)
    @eval begin
        broadcasted(::LazyArrayStyle{1}, ::typeof($op), r::AbstractRange) =
            broadcast(DefaultArrayStyle{1}(), $op, r)
    end
end

for op in (-, +, *, /)
    @eval broadcasted(::LazyArrayStyle{1}, ::typeof($op), r::AbstractRange, x::Real) =
        broadcast(DefaultArrayStyle{1}(), $op, r, x)
end

for op in (-, +, *, \)
    @eval broadcasted(::LazyArrayStyle{1}, ::typeof($op), x::Real, r::AbstractRange) =
        broadcast(DefaultArrayStyle{1}(), $op, x, r)
end


broadcasted(::LazyArrayStyle{N}, op, r::AbstractFill{T,N}) where {T,N} =
    broadcast(DefaultArrayStyle{N}(), op, r)
broadcasted(::LazyArrayStyle{N}, op, r::AbstractFill{T,N}, x::Number) where {T,N} =
    broadcast(DefaultArrayStyle{N}(), op, r, x)
broadcasted(::LazyArrayStyle{N}, op, x::Number, r::AbstractFill{T,N}) where {T,N} =
    broadcast(DefaultArrayStyle{N}(), op, x, r)
broadcasted(::LazyArrayStyle{N}, op, r1::AbstractFill{T,N}, r2::AbstractFill{V,N}) where {T,V,N} =
    broadcast(DefaultArrayStyle{N}(), op, r1, r2)

broadcasted(::LazyArrayStyle{N}, ::typeof(*), a::Zeros{T,N}, b::Zeros{V,N}) where {T,V,N} =
    broadcast(DefaultArrayStyle{N}(), *, a, b)
broadcasted(::LazyArrayStyle{N}, ::typeof(*), a::AbstractArray{T,N}, b::Zeros{V,N}) where {T,V,N} =
    broadcast(DefaultArrayStyle{N}(), *, a, b)
broadcasted(::LazyArrayStyle{N}, ::typeof(*), a::Zeros{T,N}, b::AbstractArray{V,N}) where {T,V,N} =
    broadcast(DefaultArrayStyle{N}(), *, a, b)

const Add = BroadcastArray{<:Any, <:Any, <:Broadcasted{<:Any, <:Any, typeof(+)}}
const AddVector = Add{<:Any, 1}
const AddMatrix = Add{<:Any, 2}

"""
    Add(A1, A2, …, AN)

A lazy representation of `A1 .+ A2 .+ … .+ AN`; i.e., a shorthand for `BroadcastArray(+, A1, A2, …, AN)`.
"""
Add(As...) = BroadcastArray(+, As...)
