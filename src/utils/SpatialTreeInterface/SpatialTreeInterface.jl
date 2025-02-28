module SpatialTreeInterface

import ..LoopStateMachine: @controlflow

import Extents
import GeoInterface as GI
import AbstractTrees

# ## Interface
# Interface definition for spatial tree types.
# There is no abstract supertype here since it's impossible to enforce,
# but we do have a few methods that are common to all spatial tree types.

"""
    isspatialtree(tree)::Bool

Return true if the object is a spatial tree, false otherwise.

## Implementation notes

For type stability, if your spatial tree type is `MyTree`, you should define
`isspatialtree(::Type{MyTree}) = true`, and `isspatialtree(::MyTree)` will forward
to that method automatically.
"""
isspatialtree(::T) where T = isspatialtree(T)
isspatialtree(::Type{<: Any}) = false


"""
    getchild(node)

Return an iterator over all the children of a node.
This may be materialized if necessary or available,
but can also be lazy (like a generator).
"""
getchild(node) = AbstractTrees.children(node)

"""
    getchild(node, i)

Return the `i`-th child of a node.
"""
getchild(node, i) = getchild(node)[i]

"""
    nchild(node)

Return the number of children of a node.
"""
nchild(node) = length(getchild(node))

"""
    isleaf(node)

Return true if the node is a leaf node, i.e., there are no "children" below it.
[`getchild`](@ref) should still work on leaf nodes, though, returning an iterator over the extents stored in the node - and similarly for `getnodes.`
"""
isleaf(node) = error("isleaf is not implemented for node type $(typeof(node))")

"""
    child_indices_extents(node)

Return an iterator over the indices and extents of the children of a node.

Each value of the iterator should take the form `(i, extent)`.
"""
function child_indices_extents(node)
    return zip(1:nchild(node), getchild(node))
end

# ## Query functions
# These are generic functions that work with any spatial tree type that implements the interface.


"""
    do_query(f, predicate, tree)

Call `f(i)` for each index `i` in the tree that satisfies `predicate(extent(i))`.

This is generic to anything that implements the SpatialTreeInterface, particularly the methods
[`isleaf`](@ref), [`getchild`](@ref), and [`child_extents`](@ref).
"""
function do_query(f::F, predicate::P, node::N) where {F, P, N}
    if isleaf(node)
        for (i, leaf_geometry_extent) in child_indices_extents(node)
            if predicate(leaf_geometry_extent)
                @controlflow f(i)
            end
        end
    else
        for child in getchild(node)
            if predicate(GI.extent(child))
                do_query(f, predicate, child)
            end
        end
    end
end

function do_query(predicate, node)
    a = Int[]
    do_query(Base.Fix1(push!, a), predicate, node)
    return a
end



"""
    do_dual_query(f, predicate, node1, node2)

Call `f(i1, i2)` for each index `i1` in `node1` and `i2` in `node2` that satisfies `predicate(extent(i1), extent(i2))`.

This is generic to anything that implements the SpatialTreeInterface, particularly the methods
[`isleaf`](@ref), [`getchild`](@ref), and [`child_extents`](@ref).
"""
function do_dual_query(f::F, predicate::P, node1::N1, node2::N2) where {F, P, N1, N2}
    if isleaf(node1) && isleaf(node2)
        # both nodes are leaves, so we can just iterate over the indices and extents
        for (i1, extent1) in child_indices_extents(node1)
            for (i2, extent2) in child_indices_extents(node2)
                if predicate(extent1, extent2)
                    @controlflow f(i1, i2)
                end
            end
        end
    elseif isleaf(node1) # node2 is not a leaf, node1 is - recurse further into node2
        for child in getchild(node2)
            if predicate(GI.extent(node1), GI.extent(child))
                do_dual_query(f, predicate, node1, child)
            end
        end
    elseif isleaf(node2) # node1 is not a leaf, node2 is - recurse further into node1
        for child in getchild(node1)
            if predicate(GI.extent(child), GI.extent(node2))
                do_dual_query(f, predicate, child, node2)
            end
        end
    else # neither node is a leaf, recurse into both children
        for child1 in getchild(node1)
            for child2 in getchild(node2)
                if predicate(GI.extent(child1), GI.extent(child2))
                    do_dual_query(f, predicate, child1, child2)
                end
            end
        end
    end
end

# Finally, here's a sample implementation of the interface for STRtrees

using SortTileRecursiveTree: STRtree, STRNode, STRLeafNode

nchild(tree::STRtree) = nchild(tree.rootnode)
getchild(tree::STRtree) = getchild(tree.rootnode)
getchild(tree::STRtree, i) = getchild(tree.rootnode, i)
isleaf(tree::STRtree) = isleaf(tree.rootnode)
child_indices_extents(tree::STRtree) = child_indices_extents(tree.rootnode)


nchild(node::STRNode) = length(node.children)
getchild(node::STRNode) = node.children
getchild(node::STRNode, i) = node.children[i]
isleaf(node::STRNode) = false # STRNodes are not leaves by definition

isleaf(node::STRLeafNode) = true
child_indices_extents(node::STRLeafNode) = zip(node.indices, node.extents)

end

