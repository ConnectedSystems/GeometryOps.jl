# # Performance benchmarks

# We'll benchmark GeometryOps.jl against LibGEOS, which is what most common geometry operations packages (across languages) seem to depend on.

# First, we'll load the desired packages:
import GeoInterface as GI, 
    GeometryBasics as GB,
    GeometryOps as GO, 
    LibGEOS as LG
import GeoInterface, GeometryBasics, GeometryOps, LibGEOS
using BenchmarkTools, Statistics
using GeoJSON # to generate and manipulate geometry
using CairoMakie, MakieThemes, GeoInterfaceMakie # to visualize and understand what exactly we're doing
using DataInterpolations # to upscale and downscale geometry

GeoInterfaceMakie.@enable GeoJSON.AbstractGeometry
GeoInterfaceMakie.@enable LibGEOS.AbstractGeometry
GeoInterfaceMakie.@enable GeoInterface.Wrappers.WrapperGeometry


# We include some basic plotting utilities here!
include(joinpath(@__DIR__, "utils.jl"))

# We also fetch our data early on, just so it doesn't get lost.

# #### Good old USA

fc = GeoJSON.read(read(download("https://rawcdn.githack.com/nvkelso/natural-earth-vector/ca96624a56bd078437bca8184e78163e5039ad19/geojson/ne_10m_admin_0_countries.geojson")))
usa_multipoly = fc.geometry[findfirst(==("United States of America"), fc.NAME)] |> x -> GI.convert(LibGEOS, x) |> LibGEOS.makeValid |> GO.tuples
areas = [GO.area(p) for p in GI.getgeom(usa_multipoly)]
usa_poly = GI.getgeom(usa_multipoly, findmax(areas)[2])
center_of_the_world = GO.centroid(usa_poly)
usa_poly_reflected = GO.apply(GI.PointTrait, usa_poly) do point
    x, y = GI.x(point), GI.y(point)
    return (-(x - GI.x(center_of_the_world)) + GI.x(center_of_the_world), y)
end

f, a, p = poly(usa_poly; color = Makie.wong_colors(0.5)[1], label = "Original", axis = (; title = "Good old U.S.A.", aspect = DataAspect()))
poly!(usa_poly_reflected; color = Makie.wong_colors(0.5)[2], label = "Reversed")
Legend(f[2, 1], a; valign = 0, orientation = :horizontal)
f

# In order to make this fair, we will each package's native representation as input to their benchmarks.
lg_and_go(geometry) = (GI.convert(LibGEOS, geometry), GO.tuples(geometry))

# and in order to assess how hard a problem was, we must know the number of points in the geometry.
_absolute_unit(args...) = 1
n_total_points(geom) = GO.applyreduce(_absolute_unit, +,  GI.PointTrait, geom; init = 0)

# We set up a benchmark suite in order to understand exactly what will happen:
suite = BenchmarkGroup()

# # Polygon benchmarks


# Let's look at the simple case of a circle.
points = Point2f.((cos(θ) for θ in LinRange(0, 2π, 10000)), (sin(θ) for θ in LinRange(0, 2π, 10000)))

# We'll use this circle as a polygon for our benchmarks.
circle = GI.Wrappers.Polygon([points, GB.decompose(Point2f, GB.Circle(Point2f(0.25, 0.25), 0.5))])
closed_circle = GO.ClosedRing()(GO.tuples(circle))
Makie.poly(circle; axis = (; aspect = DataAspect()))
# Now, we materialize our LibGEOS circles;
lg_circle, go_circle = lg_and_go(closed_circle)

# ## Area

# Let's start with the area of the circle.
circle_area_suite = BenchmarkGroup()

# We compute the area of the circle at different resolutions!
n_points_values = [10, 100, 1000, 10000, 100000]
for n_points in n_points_values
    circle = GI.Wrappers.Polygon([tuple.((cos(θ) for θ in LinRange(0, 2π, n_points)), (sin(θ) for θ in LinRange(0, 2π, n_points)))])
    closed_circle = GO.ClosedRing()(circle)
    lg_circle, go_circle = lg_and_go(closed_circle)
    circle_area_suite["GeometryOps"][n_points] = @benchmarkable GO.area($go_circle)
    circle_area_suite["LibGEOS"][n_points]     = @benchmarkable LG.area($lg_circle)
end

BenchmarkTools.tune!(circle_area_suite)
@time circle_area_result = BenchmarkTools.run(circle_area_suite)

# We now have the benchmark results, and we can visualize them.

plot_trials(circle_area_result, "Area")

# ## Difference, intersection, union

circle_suite = BenchmarkGroup()
circle_difference_suite = circle_suite["difference"]
circle_intersection_suite = circle_suite["intersection"]
circle_union_suite = circle_suite["union"]

n_points_values = round.(Int, exp10.(LinRange(1, 4, 10)))
for n_points in n_points_values
    circle = GI.Wrappers.Polygon([tuple.((cos(θ) for θ in LinRange(0, 2π, n_points)), (sin(θ) for θ in LinRange(0, 2π, n_points)))])
    closed_circle = GO.ClosedRing()(circle)

    lg_circle_right, go_circle_right = lg_and_go(closed_circle)

    circle_left = GO.apply(GI.PointTrait, closed_circle) do point
        x, y = GI.x(point), GI.y(point)
        return (x+0.6, y)
    end
    lg_circle_left, go_circle_left = lg_and_go(circle_left)
    circle_difference_suite["GeometryOps"][n_points] = @benchmarkable GO.difference($go_circle_left, $go_circle_right; target = GI.PolygonTrait)
    circle_difference_suite["LibGEOS"][n_points]     = @benchmarkable LG.difference($lg_circle_left, $lg_circle_right)
    circle_intersection_suite["GeometryOps"][n_points] = @benchmarkable GO.intersection($go_circle_left, $go_circle_right; target = GI.PolygonTrait)
    circle_intersection_suite["LibGEOS"][n_points]     = @benchmarkable LG.intersection($lg_circle_left, $lg_circle_right)
    circle_union_suite["GeometryOps"][n_points] = @benchmarkable GO.union($go_circle_left, $go_circle_right; target = GI.PolygonTrait)
    circle_union_suite["LibGEOS"][n_points]     = @benchmarkable LG.union($lg_circle_left, $lg_circle_right)
end

@time BenchmarkTools.tune!(circle_suite)
@time circle_result = BenchmarkTools.run(circle_suite; seconds = 3)

# Now, we plot!

# ### Difference
plot_trials(circle_result["difference"], "Difference")

# ### Intersection
plot_trials(circle_result["intersection"], "Intersection")

# ### Union
plot_trials(circle_result["union"], "Union")

usa_o_lg, usa_o_go = lg_and_go(usa_poly)
usa_r_lg, usa_r_go = lg_and_go(usa_poly_reflected)

# First, we'll test union:
printstyled("LibGEOS"; color = :red, bold = true)
println()
@benchmark LG.union($usa_o_lg, $usa_r_lg)
printstyled("GeometryOps"; color = :blue, bold = true)
println()
@benchmark GO.union($usa_o_go, $usa_r_go; target = GI.PolygonTrait)

# Next, intersection:
printstyled("LibGEOS"; color = :red, bold = true)
println()
@benchmark LG.intersection($usa_o_lg, $usa_r_lg)
printstyled("GeometryOps"; color = :blue, bold = true)
println()
@benchmark GO.intersection($usa_o_go, $usa_r_go; target = GI.PolygonTrait)

# and finally the difference:
printstyled("LibGEOS"; color = :red, bold = true)
println()
@benchmark lg_diff = LG.difference(usa_o_lg, usa_r_lg)
printstyled("GeometryOps"; color = :blue, bold = true)
println()
@benchmark go_diff = GO.difference(usa_o_go, usa_r_go; target = GI.PolygonTrait)

# You can see clearly that GeometryOps is currently losing out to LibGEOS.  Our algorithms aren't optimized for large polygons and we're paying the price for that.

# It's heartening that the polygon complexity isn't making too much of a difference; the difference in performance is mostly due to the number of vertices, as we can see from the circle benchmarks as well.

# # OGC functions

# We'll test the OGC functions using some constructed geometries, as well as some loaded ones.

# In order to do this, we must understand the length of the geometry, so we first get the number of points:
n_total_points(usa_multipoly)

GO.simplify(usa_multipoly; ratio = 0.1) |> poly |> n_total_points

geom_method_suite = BenchmarkGroup()

centroid_suite = BenchmarkGroup() # geom_method_suite["centroid"]
for frac in exp10.(LinRange(log10(0.01), log10(0.6), 6))
    geom = GO.simplify(usa_multipoly; ratio = frac)
    geom_lg, geom_go = lg_and_go(geom)
    centroid_suite["GeometryOps"][n_total_points(geom)] = @benchmarkable GO.centroid($geom_go)
    centroid_suite["LibGEOS"][n_total_points(geom)] = @benchmarkable LG.centroid($geom_lg)
    centroid_suite["GeometryOps threaded"][n_total_points(geom)] = @benchmarkable GO.centroid($geom_go; threaded = GO._True())
end

const var"hello there my old friend" = GO.simplify(usa_multipoly; ratio = 0.01)
ProfileView.@profview GO.centroid(var"hello there my old friend")

@time BenchmarkTools.tune!(centroid_suite)
@time centroid_result = BenchmarkTools.run(centroid_suite)
fig = plot_trials(centroid_result, "Centroid on USA")
contents(fig.layout)[1].subtitle = "" #"Natural Earth's full USA, simplified down"
fig

# Now, to understand the dynamics on a per-vertex basis, we will test the centroid of a circle.

circle_centroid_suite = BenchmarkGroup()# geom_method_suite["centroid_circle"]
for e in LinRange(1, 3, 10)
    n_points = round(Int, 10^e)
    circle = GI.Wrappers.Polygon([tuple.((cos(θ) for θ in LinRange(0, 2π, n_points)), (sin(θ) for θ in LinRange(0, 2π, n_points)))])
    closed_circle = GO.ClosedRing()(circle)
    lg_circle, go_circle = lg_and_go(closed_circle)
    circle_centroid_suite["GeometryOps"][n_points] = @benchmarkable GO.centroid($go_circle)
    circle_centroid_suite["LibGEOS"][n_points]     = @benchmarkable LG.centroid($lg_circle)
    circle_centroid_suite["GeometryOps threaded"][n_points] = @benchmarkable GO.centroid($go_circle; threaded = GO._True())
end

@time BenchmarkTools.tune!(circle_centroid_suite)
@time centroid_result = BenchmarkTools.run(circle_centroid_suite)
fig = plot_trials(centroid_result, "Circle")
contents(fig.layout)[1].subtitle = ""
fig
# contents(fig.layout)[1].subtitle = "Natural Earth's full USA, simplified down"

n_points = 3000
circle = GI.Wrappers.Polygon([tuple.((cos(θ) for θ in LinRange(0, 2π, n_points)), (sin(θ) for θ in LinRange(0, 2π, n_points)))])
closed_circle = GO.ClosedRing()(circle)
lg_circle, go_circle = lg_and_go(closed_circle);
const ___go_c = go_circle
function _do_profile(go_c)
    for _ in 1:100
        GO.centroid(go_c)
    end
end

ProfileView.@profview _do_profile(___go_c)

# ## Within

within_suite = BenchmarkGroup()# geom_method_suite["within"]
for frac in exp10.(LinRange(log10(0.1), log10(1), 10))
    geom = GO.simplify(usa_multipoly; ratio = frac)
    geom_valid = LibGEOS.makeValid(GI.convert(LibGEOS, geom));
    geom_lg, geom_go = lg_and_go(geom_valid);
    centroid = GO.centroid(geom_go)
    @test GI.x(GO.centroid(geom_go)) ≈ GI.x(LG.centroid(geom_lg))
    @test GI.y(GO.centroid(geom_go)) ≈ GI.y(LG.centroid(geom_lg))
    centroid_lg, centroid_go = lg_and_go(centroid)
    within_suite["GeometryOps"][n_total_points(geom)] = @benchmarkable GO.within($centroid_go, $geom_go)
    within_suite["LibGEOS"][n_total_points(geom)] = @benchmarkable LG.within($centroid_lg, $geom_lg)
    @test GO.within(centroid_go, geom_go) == LG.within(centroid_lg, geom_lg)
end

@time BenchmarkTools.tune!(within_suite)
@time within_result = BenchmarkTools.run(within_suite)
fig = plot_trials(within_result, "Within")
contents(fig.layout)[1].subtitle = "Test that centroid is within multipoly"
fig


# ## Overlaps


overlaps_suite = BenchmarkGroup()# geom_method_suite["overlaps"]
for frac in exp10.(LinRange(log10(0.1), log10(1), 10))
    geom = GO.simplify(usa_multipoly; ratio = frac)
    geom_valid = LibGEOS.makeValid(GI.convert(LibGEOS, geom)) |> GO.tuples;
    geom_reflected =  GO.apply(GI.PointTrait, geom_valid) do point
        x, y = GI.x(point), GI.y(point)
        return (-(x - GI.x(center_of_the_world)) + GI.x(center_of_the_world), y)
    end
    geom_lg_orig, geom_go_orig = lg_and_go(geom_valid);
    geom_lg_refl, geom_go_refl = lg_and_go(geom_reflected);
    overlaps_suite["GeometryOps"][n_total_points(geom_valid)] = @benchmarkable GO.overlaps($geom_go_orig, $geom_go_refl)
    overlaps_suite["LibGEOS"][n_total_points(geom_valid)] = @benchmarkable LG.overlaps($geom_lg_orig, $geom_lg_refl)
    @test GO.overlaps(geom_go_orig, geom_go_refl) == LG.overlaps(geom_lg_orig, geom_lg_refl)
end

@time BenchmarkTools.tune!(overlaps_suite)
@time overlaps_result = BenchmarkTools.run(overlaps_suite)
fig = plot_trials(overlaps_result, "overlaps")
contents(fig.layout)[1].subtitle = "Test that multipoly overlaps its reflected self"
fig


geom = usa_multipoly
geom_valid = LibGEOS.makeValid(GI.convert(LibGEOS, geom)) |> GO.tuples;
geom_reflected =  GO.apply(GI.PointTrait, geom_valid) do point
    x, y = GI.x(point), GI.y(point)
    return (-(x - GI.x(center_of_the_world)) + GI.x(center_of_the_world), y)
end

function _do_things(geom_valid, geom_reflected)
    for i in 1:3
        GO.overlaps(geom_valid, geom_reflected)
    end
end

ProfileView.@profview _do_things(geom_valid, geom_reflected)

# ## Simplification

# We'll test polygons and multipolygons for this, since they're the easiest to obtain,
# but from the GeometryOps end the performance is about the same.

simplify_suite = BenchmarkGroup()# geom_method_suite["simplify"]
multipoly_suite = simplify_suite["multipoly"]
for frac in exp10.(LinRange(log10(0.3), log10(1), 6))
    geom = GO.simplify(usa_multipoly; ratio = frac)
    geom_lg, geom_go = lg_and_go(geom)
    _tol = 0.001
    multipoly_suite["GO-DP"][n_total_points(geom)] = @benchmarkable GO.simplify($geom_go; tol = $_tol)
    # multipoly_suite["GO-VW"][n_total_points(geom)] = @benchmarkable GO.simplify($(GO.VisvalingamWhyatt(; tol = $_tol)), $geom_go)
    multipoly_suite["GO-RD"][n_total_points(geom)] = @benchmarkable GO.simplify($(GO.RadialDistance(; tol = _tol)), $geom_go)
    multipoly_suite["LibGEOS"][n_total_points(geom)] = @benchmarkable LG.simplify($geom_lg, $_tol)
    println("""
    For $(n_total_points(geom)) points, the algorithms generated polygons with the following number of vertices:
    GO-DP : $(n_total_points( GO.simplify(geom_go; tol = _tol)))
    GO-RD : $(n_total_points( GO.simplify((GO.RadialDistance(; tol = _tol)), geom_go)))
    LGeos : $(n_total_points( LG.simplify(geom_lg, _tol)))
    """)
    # GO-VW : $(n_total_points( GO.simplify((GO.VisvalingamWhyatt(; tol = _tol)), geom_go)))
    println()
end
singlepoly_suite = simplify_suite["singlepoly"]
for n_verts in round.(Int, exp10.(LinRange(log10(10), log10(10_000), 10)))
    geom = GI.Wrappers.Polygon(generate_random_poly(0, 0, n_verts, 2, 0.2, 0.3))
    geom_lg, geom_go = lg_and_go(LG.makeValid(GI.convert(LG, geom)))
    singlepoly_suite["GO-DP"][n_total_points(geom)] = @benchmarkable GO.simplify($geom_go; tol = 0.1)
    singlepoly_suite["GO-VW"][n_total_points(geom)] = @benchmarkable GO.simplify($(GO.VisvalingamWhyatt(; tol = 0.1)), $geom_go)
    singlepoly_suite["GO-RD"][n_total_points(geom)] = @benchmarkable GO.simplify($(GO.RadialDistance(; tol = 0.1)), $geom_go)
    singlepoly_suite["LibGEOS"][n_total_points(geom)] = @benchmarkable LG.simplify($geom_lg, 0.1)
end

@time BenchmarkTools.tune!(simplify_suite["singlepoly"]; verbose = true)
@time simplify_result = BenchmarkTools.run(simplify_suite["singlepoly"])

fig = plot_trials(simplify_result, "Simplify singlepoly"; legend_position = (1, 2), legend_orientation = :vertical, legend_valign = 0.5)
contents(fig.layout)[1].subtitle = "Tested on a random spiky polygon"
fig

@time BenchmarkTools.tune!(simplify_suite["multipoly"]; verbose = true)
@time simplify_result = BenchmarkTools.run(simplify_suite["multipoly"])

fig = plot_trials(simplify_result, "Simplify multipoly"; legend_position = (1, 2), legend_orientation = :vertical, legend_valign = 0.5)
contents(fig.layout)[1].subtitle = "Tested on the USA multipolygon"
fig
# We have to test this with multiple geometries,
# which means 