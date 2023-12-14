#===
# Plotting by Plots.jl

===#

using Plots
using Random
Random.seed!(2022)

#---

fig = plot(1:5, rand(1:6, 5))
display("image/png", fig)

# ## Runtime information

import Pkg
Pkg.status()

#---

import InteractiveUtils
InteractiveUtils.versioninfo()
