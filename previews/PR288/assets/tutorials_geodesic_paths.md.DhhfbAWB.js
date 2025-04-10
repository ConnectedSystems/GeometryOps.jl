import{_ as a,c as e,o as n,az as p}from"./chunks/framework.uBVz5atw.js";const h=JSON.parse('{"title":"Geodesic paths","description":"","frontmatter":{},"headers":[],"relativePath":"tutorials/geodesic_paths.md","filePath":"tutorials/geodesic_paths.md","lastUpdated":null}'),t={name:"tutorials/geodesic_paths.md"};function i(o,s,l,c,d,r){return n(),e("div",null,s[0]||(s[0]=[p(`<h1 id="Geodesic-paths" tabindex="-1">Geodesic paths <a class="header-anchor" href="#Geodesic-paths" aria-label="Permalink to &quot;Geodesic paths {#Geodesic-paths}&quot;">​</a></h1><p>Geodesic paths are paths computed on an ellipsoid, as opposed to a plane.</p><div class="language-@example vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">@example</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span>import GeometryOps as GO, GeoInterface as GI</span></span>
<span class="line"><span>using CairoMakie, GeoMakie</span></span>
<span class="line"><span></span></span>
<span class="line"><span></span></span>
<span class="line"><span>IAH = (-95.358421, 29.749907)</span></span>
<span class="line"><span>AMS = (4.897070, 52.377956)</span></span>
<span class="line"><span></span></span>
<span class="line"><span></span></span>
<span class="line"><span>fig, ga, _cp = lines(GeoMakie.coastlines(); axis = (; type = GeoAxis))</span></span>
<span class="line"><span>lines!(ga, GO.segmentize(GO.GeodesicSegments(; max_distance = 100_000), GI.LineString([IAH, AMS])); color = Makie.wong_colors()[2])</span></span>
<span class="line"><span>fig</span></span></code></pre></div>`,3)]))}const g=a(t,[["render",i]]);export{h as __pageData,g as default};
