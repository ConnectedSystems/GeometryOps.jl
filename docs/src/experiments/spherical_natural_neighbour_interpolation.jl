#=
# Spherical natural neighbour interpolatoin
=#

import GeometryOps as GO, GeoInterface as GI, GeoFormatTypes as GFT
import Proj # for easy stereographic projection - TODO implement in Julia
import DelaunayTriangulation as DelTri # Delaunay triangulation on the 2d plane
import CoordinateTransformations, Rotations

using Downloads # does what it says on the tin
using JSON3 # to load data
using CairoMakie, GeoMakie # for plotting
import Makie: Point3d

# include(joinpath(@__DIR__, "spherical_delaunay_stereographic.jl"))

using LinearAlgebra
using GeometryBasics

struct SphericalCap{T}
    point::Point3{T}
    radius::T
end

function SphericalCap(point::Point3{T1}, radius::T2) where {T1, T2}
    return SphericalCap{promote_type(T1, T2)}(point, radius)
end


function circumcenter_on_unit_sphere(a, b, c)
    LinearAlgebra.normalize(a × b + b × c + c × a)
end

spherical_distance(x::Point3, y::Point3) = acos(clamp(x ⋅ y, -1.0, 1.0))

"Get the circumcenter of the triangle (a, b, c) on the unit sphere.  Returns a normalized 3-vector."
function SphericalCap(a::Point3, b::Point3, c::Point3)
    circumcenter = circumcenter_on_unit_sphere(a, b, c)
    circumradius = spherical_distance(a, circumcenter)
    return SphericalCap(circumcenter, circumradius)
end

function bowyer_watson_envelope!(applicable_points, query_point, points, faces, caps = map(splat(SphericalCap), (view(cartesian_points, face) for face in faces)); applicable_cap_indices = Int64[])
    # brute force for now, but try the jump and search algorithm later
    # can use e.g GeometryBasics.decompose(Point3{Float64}, GeometryBasics.Sphere(Point3(0.0), 1.0), 5) 
    # to get starting points, or similar
    empty!(applicable_cap_indices)
    for (i, cap) in enumerate(caps)
        if cap.radius ≥ spherical_distance(query_point, cap.point)
            push!(applicable_cap_indices, i)
        end
    end
    # Now that we have the face indices, we need to get the applicable points
    empty!(applicable_points)
    for i in applicable_cap_indices
        current_face = faces[i]
        edge_reoccurs = false
        for current_edge in ((current_face[1], current_face[2]), (current_face[2], current_face[3]), (current_face[3], current_face[1]))
            for j in applicable_cap_indices
                if j == i
                    continue # can't compare a triangle to itself
                end
                face_to_compare = faces[j]
                for edge_to_compare in ((face_to_compare[1], face_to_compare[2]), (face_to_compare[2], face_to_compare[3]), (face_to_compare[3], face_to_compare[1]))
                    if edge_to_compare == current_edge || reverse(edge_to_compare) == current_edge
                        edge_reoccurs = true
                        break
                    end
                end
            end
            if !edge_reoccurs # edge is unique
                push!(applicable_points, current_edge[1])
                push!(applicable_points, current_edge[2])
            end
        end
    end
    # Start at point 1, find the first occurrence of point 1 in the applicable_points list.
    # This is the last point of the edge coming from point 1.
    # Now, swap the element before that with point 3.  Then continue on doing this.
    # for (i, point_idx) in enumerate(applicable_points)
    #     if i % 2 == 0
    #         continue
    #     end
    #     applicable_points[i] = findfirst(==(applicable_points[i+1]), points)
    # end
    return unique!(applicable_points)
end


import NaturalNeighbours: previndex_circular, nextindex_circular
function laplace_ratio(points, envelope, i #= current vertex index =#, interpolation_point)
    u = envelope[i]
    prev_u = envelope[previndex_circular(envelope, i)]
    next_u = envelope[nextindex_circular(envelope, i)]
    p = points[u]
    q, r = points[prev_u], points[next_u]
    g1 = circumcenter_on_unit_sphere(q, p, interpolation_point)
    g2 = circumcenter_on_unit_sphere(p, r, interpolation_point)
    ℓ = spherical_distance(g1, g2)
    d = spherical_distance(p, interpolation_point)
    w = ℓ / d
    return w, u, prev_u, next_u
end

struct NaturalCoordinates{F, I}
    coordinates::Vector{F}
    indices::Vector{I}
    interpolation_point::Point3{Float64}
end

function laplace_nearest_neighbour_coords(points, faces, interpolation_point; envelope = Int64[], cap_idxs = Int64[])
    envelope = bowyer_watson_envelope!(envelope, interpolation_point, points, faces, caps; applicable_cap_indices = cap_idxs)
    coords = NaturalCoordinates(Float64[], Int64[], interpolation_point)
    for i in eachindex(envelope)
        w, u, prev_u, next_u = laplace_ratio(points, envelope, i, interpolation_point)
        push!(coords.coordinates, w)
        push!(coords.indices, u)
    end
    coords.coordinates ./= sum(coords.coordinates)
    return coords
end

function eval_laplace_coordinates(points, faces, zs, interpolation_point)
    coords = laplace_nearest_neighbour_coords(points, faces, interpolation_point)
    if isempty(coords.coordinates)
        return NaN
    end
    return sum((coord * zs[idx] for (coord, idx) in zip(coords.coordinates, coords.indices)))
end





# These points are known to be good points, i.e., lon, lat, alt
geographic_points = Point3{Float64}.(JSON3.read(read(Downloads.download("https://gist.githubusercontent.com/Fil/6bc12c535edc3602813a6ef2d1c73891/raw/3ae88bf307e740ddc020303ea95d7d2ecdec0d19/points.json"), String)))
z_values = last.(geographic_points)
faces = spherical_triangulation(geographic_points)
# correct the faces, since the order seems to be off
faces = reverse.(faces)

unique!(sort!(reduce(vcat, faces))) # so how am I getting this index?

cartesian_points = UnitCartesianFromGeographic().(geographic_points)

caps = map(splat(SphericalCap), (view(cartesian_points, face) for face in faces))

lons = -180.0:0.5:180.0
lats = -90.0:0.5:90.0

eval_laplace_coordinates(cartesian_points, faces, z_values, Point3(1.0, 0.0, 0.0))

values = map(UnitCartesianFromGeographic().(Point2.(lons, lats'))) do point
    eval_laplace_coordinates(cartesian_points, faces, z_values, point)
end

heatmap(lons, lats, values; axis = (; aspect = DataAspect()))

f = Figure();
a = LScene(f[1, 1])
p = meshimage!(a, lons, lats, rotl90(values); npoints = (720, 360))
p.transformation.transform_func[] = Makie.PointTrans{3}(UnitCartesianFromGeographic())
# scatter!(a, cartesian_points)
f # not entirely sure what's going on here
# diagnostics
# f, a, p = scatter(reduce(vcat, (view(cartesian_points, face) for face in view(faces, neighbour_inds))))
# scatter!(query_point; color = :red, markersize = 40)

query_point = LinearAlgebra.normalize(Point3(1.0, 1.0, 0.0))
pt_inds = bowyer_watson_envelope!(Int64[], query_point, cartesian_points, faces, caps)

f, a, p = scatter([query_point]; markersize = 30, color = :green, axis = (; type = LScene));
scatter!(a, cartesian_points)
scatter!(a, view(cartesian_points, pt_inds); color = eachindex(pt_inds), colormap = :turbo, markersize = 20)
wireframe!(a, GeometryBasics.Mesh(cartesian_points, faces); alpha = 0.3)
f

function Makie.convert_arguments(::Type{Makie.Mesh}, cap::SphericalCap)
    offset_point = LinearAlgebra.normalize(cap.point + LinearAlgebra.normalize(Point3(cos(cap.radius), sin(cap.radius), 0.0)))
    points = [cap.point + Rotations.AngleAxis(θ, cap.point...) * offset_point for θ in LinRange(0, 2π, 20)]
    push!(points, cap.point)
    faces = [GeometryBasics.TriangleFace(i, i+1, 21) for i in 1:19]
    return (GeometryBasics.normal_mesh(points, faces),)
end
