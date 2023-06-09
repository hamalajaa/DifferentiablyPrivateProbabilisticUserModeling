using ArgParse
using BSON
using Distributions
using Flux
using Stheno
using Tracker
using Statistics
using Printf

include("../../NeuralProcesses.jl/src/NeuralProcesses.jl")
include("../../NeuralProcesses.jl/src/experiment/experiment.jl")

using .NeuralProcesses
using .NeuralProcesses.Experiment

parser = ArgParseSettings()
@add_arg_table! parser begin
    "--gen"
        help = "Experiment setting: gridworld, menu_search, h_menu_search"
        arg_type = String
        default = "gridworld"
    "--n_traj"
        help = "Number of context trajectories. Should be fixed to 10 for testing."
        arg_type = Int
        default = 10
    "--n_epochs"
        help = "Number of total epochs."
        arg_type = Int
        default = 100
    "--batch_size"
        help = "Batch size."
        arg_type = Int
        default = 1
    "--bson"
        help = "Directly specify the file to save the model to and load it from."
        arg_type = String
    "--bson_r"
        help = "Directory/filename where the results are saved to."
        arg_type = String
end
args = parse_args(parser)

batch_size  = args["batch_size"]

x_context = Distributions.Uniform(-2, 2)
x_target  = Distributions.Uniform(-2, 2)

num_context = Distributions.DiscreteUniform(50, 50)
num_target  = Distributions.DiscreteUniform(50, 50)

data_gen = NeuralProcesses.DataGenerator(
                MCTSPlanner(args;),
                batch_size=batch_size,
                x_context=x_context,
                x_target=x_target,
                num_context=num_context,
                num_target=num_target,
                σ²=1e-8
	    )

likelihoods(xs...) = NeuralProcesses.likelihood(
		        xs...,
		        target=true,
		        num_samples=5,
		        fixed_σ_epochs=3
		    )

n_batches = 128

# Generate evaluation data
@time data = gen_batch(data_gen, n_batches)

all_res = []

for iter in 1:args["n_epochs"]

    res = []

    @printf("Number of iterations: %d", iter)

    model = NeuralProcesses.Experiment.recent_model("models/ex1/dp/"*string(args["bson"])*"/"*string(iter)*".bson") |> gpu

    # Loop over the number of trajectories
    for i in 0:9

        # Init a list for processed data
        d = []

        # Loop over data batches
        for j in 1:n_batches
            
            # Manually split data into context and target sets
            xc, yc, xt, yt = data[j]
            start_idx = 10*(9-i)+1
            push!(d, [xc[start_idx:end,:,:], yc[:,start_idx:end,:], xt, yt])

        end

        tuples = map(x -> likelihoods(model, 0, gpu.(x)...), d)
        
        _mean_error(xs) = (Statistics.mean(xs), 2std(xs) / sqrt(length(xs)))

        values = map(x -> x[1], tuples)
        sizes  = map(x -> x[2], tuples)

        lik_value, lik_error = _mean_error(values)
        @printf("Likelihood at %d context trajectories", i)
        @printf(
            "	%8.3f +- %7.3f (%d batches)\n",
            lik_value,
            lik_error,
            n_batches
        )

        push!(res, (lik_value, lik_error))

    end

    push!(all_res, res)

end

BSON.bson(args["bson_r"], res=all_res)



