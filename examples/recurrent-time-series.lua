-- This is a multi-variate version of the time-series example 
-- at https://github.com/Element-Research/rnn#rnn.Recurrent
require 'rnn'

-- experiment setup
rho = 5 -- maximum number of time steps for BPTT
inputSize = 6
hiddenSize = 10
outputSize = 6
nIndex = 100

-- toy dataset (task is to predict next vector, given previous)
-- following the normal distribution 
-- note: vX is used as both input X and output Y to save memory
local function evalPDF(vMean, vSigma, vX)
   for i=1,vMean:size(1) do
      local b = (vX[i]-vMean[i])/vSigma[i]
      vX[i] = math.exp(-b*b/2)/(vSigma[i]*math.sqrt(2*math.pi))
   end
   return vX
end
vBias = torch.randn(inputSize)
vMean = torch.Tensor(inputSize):fill(5)
vSigma = torch.linspace(1,inputSize/2.0,inputSize)
sequence = torch.Tensor(nIndex, inputSize)
j = 0
for i=1,nIndex do
  sequence[{i,{}}]:fill(j)
  evalPDF(vMean, vSigma, sequence[{i,{}}])
  sequence[{i,{}}]:add(vBias)
  j = j + 1
  if j>10 then j = 0 end
end
print('Sequence:'); print(sequence)

-- batch mode
batchSize = 8
offsets = {}
for i=1,batchSize do
   --table.insert(offsets, i)
   -- randomize batch input
   table.insert(offsets, math.ceil(math.random()*batchSize))
end
offsets = torch.LongTensor(offsets)

-- RNN
r = nn.Recurrent(
   hiddenSize, -- size of output
   nn.Linear(inputSize, hiddenSize), -- input layer
   nn.Linear(hiddenSize, hiddenSize), -- recurrent layer
   nn.Sigmoid(), -- transfer function
   rho
)

rnn = nn.Sequential()
   :add(r)
   :add(nn.Linear(hiddenSize, outputSize))

criterion = nn.MSECriterion() 

-- wrap rnn in to a Recursor
rnn = nn.Recursor(rnn, rho)
rnn:zeroGradParameters()
-- rnn uses backwardOnline by default
--rnn:backwardOnline()

-- use Sequencer for better data handling
rnn = nn.Sequencer(rnn)
criterion = nn.SequencerCriterion(criterion)
print(rnn)

-- train rnn model
lr = 0.001 -- learning rate
nIterations = 1000 -- max loop number
minErr = outputSize -- report min error
minK = 0
avgErrs = torch.Tensor(nIterations):fill(0)
for k = 1, nIterations do --while true do
   -- 1. create a sequence of rho time-steps
   local inputs, targets = {}, {}
   for step = 1, rho do
      -- batch of inputs
      inputs[step] = sequence:index(1, offsets)
      -- batch of targets
      offsets:add(1) -- increase indices by 1
      offsets[offsets:gt(nIndex)] = 1
      targets[step] = sequence:index(1, offsets)
   end

   -- 2. forward sequence through rnn
   rnn:zeroGradParameters()

   local outputs = rnn:forward(inputs)

   -- report errors
   local err = criterion:forward(outputs, targets)
   print('Iter: ' .. k .. '   Err: ' .. err)
   --print(' Input:  ', inputs); print(' Output: ', outputs); print(' Target: ', targets)
   avgErrs[k] = err
   if avgErrs[k] < minErr then
      minErr = avgErrs[k]
      minK = k
   end

   -- 3. backward sequence through rnn (i.e. backprop through time)
   local gradOutputs = criterion:backward(outputs, targets)
   local gradInputs = rnn:backward(inputs, gradOutputs)

   -- 4. updates parameters
   rnn:updateParameters(lr)
end -- nIterations

--print(avgErrs)
print('min err: ' .. minErr .. ' on iteration ' .. minK)
