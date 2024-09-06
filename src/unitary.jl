module Unitary

# unitary U
# tangent vectors Δ = U*A with A' = -A

using TensorKit
import TensorKit: similarstoragetype, SectorDict
using ..TensorKitManifolds: projectantihermitian!, projectisometric!, PolarNewton
import ..TensorKitManifolds: base, checkbase, inner, retract, transport, transport!

struct UnitaryTangent{T<:AbstractTensorMap,TA<:AbstractTensorMap}
    W::T
    A::TA
    function UnitaryTangent(W::AbstractTensorMap{E₁,S,N₁,N₂},
                            A::AbstractTensorMap{E₂,S,N₂,N₂}) where {E₁,E₂,S,N₁,N₂}
        T = typeof(W)
        TA = typeof(A)
        return new{T,TA}(W, A)
    end
end
Base.copy(Δ::UnitaryTangent) = UnitaryTangent(Δ.W, copy(Δ.A))
Base.getindex(Δ::UnitaryTangent) = Δ.W * Δ.A
base(Δ::UnitaryTangent) = Δ.W
function checkbase(Δ₁::UnitaryTangent, Δ₂::UnitaryTangent)
    return Δ₁.W == Δ₂.W ? Δ₁.W :
           throw(ArgumentError("tangent vectors with different base points"))
end

# Basic vector space behaviour
function Base.:+(Δ₁::UnitaryTangent, Δ₂::UnitaryTangent)
    return UnitaryTangent(checkbase(Δ₁, Δ₂), Δ₁.A + Δ₂.A)
end
function Base.:-(Δ₁::UnitaryTangent, Δ₂::UnitaryTangent)
    return UnitaryTangent(checkbase(Δ₁, Δ₂), Δ₁.A - Δ₂.A)
end
Base.:-(Δ::UnitaryTangent) = (-1) * Δ

Base.:*(Δ::UnitaryTangent, α::Real) = rmul!(copy(Δ), α)
Base.:*(α::Real, Δ::UnitaryTangent) = lmul!(α, copy(Δ))
Base.:/(Δ::UnitaryTangent, α::Real) = rmul!(copy(Δ), inv(α))
Base.:\(α::Real, Δ::UnitaryTangent) = lmul!(inv(α), copy(Δ))

Base.zero(Δ::UnitaryTangent) = UnitaryTangent(Δ.W, zero(Δ.A))

function TensorKit.rmul!(Δ::UnitaryTangent, α::Real)
    rmul!(Δ.A, α)
    return Δ
end
function TensorKit.lmul!(α::Real, Δ::UnitaryTangent)
    lmul!(α, Δ.A)
    return Δ
end
function TensorKit.axpy!(α::Real, Δx::UnitaryTangent, Δy::UnitaryTangent)
    checkbase(Δx, Δy)
    axpy!(α, Δx.A, Δy.A)
    return Δy
end
function TensorKit.axpby!(α::Real, Δx::UnitaryTangent, β::Real, Δy::UnitaryTangent)
    checkbase(Δx, Δy)
    axpby!(α, Δx.A, β, Δy.A)
    return Δy
end

function TensorKit.dot(Δ₁::UnitaryTangent, Δ₂::UnitaryTangent)
    checkbase(Δ₁, Δ₂)
    return dot(Δ₁.A, Δ₂.A)
end
TensorKit.norm(Δ::UnitaryTangent, p::Real=2) = norm(Δ.A, p)

# tangent space methods
function inner(W::AbstractTensorMap, Δ₁::UnitaryTangent, Δ₂::UnitaryTangent;
               metric=:euclidean)
    @assert metric == :euclidean
    return Δ₁ === Δ₂ ? norm(Δ₁)^2 : real(dot(Δ₁, Δ₂))
end
function project!(X::AbstractTensorMap, W::AbstractTensorMap; metric=:euclidean)
    @assert metric == :euclidean
    P = W' * X
    A = projectantihermitian!(P)
    return UnitaryTangent(W, A)
end
project(X, W; metric=:euclidean) = project!(copy(X), W; metric=:euclidean)

# geodesic retraction, coincides with Stiefel retraction (which is not geodesic for p < n)
function retract(W::AbstractTensorMap, Δ::UnitaryTangent, α; alg=nothing)
    W == base(Δ) || throw(ArgumentError("not a valid tangent vector at base point"))
    E = exp(α * Δ.A)
    W′ = projectisometric!(W * E; alg=SDD())
    A′ = Δ.A
    return W′, UnitaryTangent(W′, A′)
end

# isometric vector transports compatible with above retraction
# (also with differential of retraction)
function transport!(Θ::UnitaryTangent, W::AbstractTensorMap, Δ::UnitaryTangent, α::Real, W′;
                    alg=:stiefel)
    if alg == :parallel
        return transport_parallel!(Θ, W, Δ, α, W′)
    elseif alg == :stiefel
        return transport_stiefel!(Θ, W, Δ, α, W′)
    else
        throw(ArgumentError("unknown algorithm: `alg = $metric`"))
    end
end
function transport(Θ::UnitaryTangent, W::AbstractTensorMap, Δ::UnitaryTangent, α::Real, W′;
                   alg=:stiefel)
    return transport!(copy(Θ), W, Δ, α, W′; alg=alg)
end

# transport_parallel correspondings to the torsion-free Levi-Civita connection
# transport_stiefel is compatible to Stiefel.transport and corresponds to a non-torsion-free
# connection
function transport_parallel!(Θ::UnitaryTangent, W::AbstractTensorMap, Δ::UnitaryTangent, α,
                             W′)
    W == checkbase(Δ, Θ) || throw(ArgumentError("not a valid tangent vector at base point"))
    E = exp((α / 2) * Δ.A)
    A′ = projectantihermitian!(E' * Θ.A * E) # exra projection for stability
    return UnitaryTangent(W′, A′)
end
function transport_parallel(Θ::UnitaryTangent, W::AbstractTensorMap, Δ::UnitaryTangent, α,
                            W′)
    return transport_parallel!(copy(Θ), W, Δ, α, W′)
end

function transport_stiefel!(Θ::UnitaryTangent, W::AbstractTensorMap, Δ::UnitaryTangent,
                            α, W′)
    W == checkbase(Δ, Θ) || throw(ArgumentError("not a valid tangent vector at base point"))
    A′ = Θ.A
    return UnitaryTangent(W′, A′)
end
function transport_stiefel(Θ::UnitaryTangent, W::AbstractTensorMap, Δ::UnitaryTangent,
                           α, W′)
    return transport_stiefel!(copy(Θ), W, Δ, α, W′)
end

end
