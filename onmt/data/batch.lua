--[[ Return the maxLength, sizes, and non-zero count
  of a batch of `seq`s ignoring `ignore` words.
--]]
local function getLength(seq, ignore)
  local sizes = torch.IntTensor(#seq):zero()
  local max = 0
  local sum = 0

  for i = 1, #seq do
    local len = seq[i]:size(1)
    if ignore ~= nil then
      len = len - ignore
    end
    max = math.max(max, len)
    sum = sum + len
    sizes[i] = len
  end
  return max, sizes, sum
end

--[[ Data management and batch creation.

Batch interface [size]:

  * size: number of sentences in the batch [1]
  * sourceLength: max length in source batch [1]
  * sourceSize:  lengths of each source [batch x 1]
  * sourceInput:  left-padded idx's of source (PPPPPPABCDE) [batch x max]
  * sourceInputFeatures: table of source features sequences
  * sourceInputRev: right-padded  idx's of source rev (EDCBAPPPPPP) [batch x max]
  * sourceInputRevFeatures: table of reversed source features sequences
  * targetLength: max length in source batch [1]
  * targetSize: lengths of each source [batch x 1]
  * targetNonZeros: number of non-ignored words in batch [1]
  * targetInput: input idx's of target (SABCDEPPPPPP) [batch x max]
  * targetInputFeatures: table of target input features sequences
  * targetOutput: expected output idx's of target (ABCDESPPPPPP) [batch x max]
  * targetOutputFeatures: table of target output features sequences

 TODO: change name of size => maxlen
--]]
local Batch = torch.class('Batch')

--[[ Create a batch object given aligned sent tables `src` and `tgt`
  (optional). Data format is shown at the top of the file.
--]]
function Batch:__init(src, srcFeatures, tgt, tgtFeatures)
  src = src or {}
  srcFeatures = srcFeatures or {}
  tgtFeatures = tgtFeatures or {}
  if tgt ~= nil then
    assert(#src == #tgt, "source and target must have the same batch size")
  end

  self.size = #src

  self.sourceLength, self.sourceSize = getLength(src)

  local sourceSeq = torch.IntTensor(self.sourceLength, self.size):fill(onmt.Constants.PAD)
  self.sourceInput = sourceSeq:clone()
  self.sourceInputRev = sourceSeq:clone()

  self.sourceInputFeatures = {}
  self.sourceInputRevFeatures = {}

  if #srcFeatures > 0 then
    for _ = 1, #srcFeatures[1] do
      table.insert(self.sourceInputFeatures, sourceSeq:clone())
      table.insert(self.sourceInputRevFeatures, sourceSeq:clone())
    end
  end

  if tgt ~= nil then
    self.targetLength, self.targetSize, self.targetNonZeros = getLength(tgt, 1)

    local targetSeq = torch.IntTensor(self.targetLength, self.size):fill(onmt.Constants.PAD)
    self.targetInput = targetSeq:clone()
    self.targetOutput = targetSeq:clone()

    self.targetInputFeatures = {}
    self.targetOutputFeatures = {}

    if #tgtFeatures > 0 then
      for _ = 1, #tgtFeatures[1] do
        table.insert(self.targetInputFeatures, targetSeq:clone())
        table.insert(self.targetOutputFeatures, targetSeq:clone())
      end
    end
  end

  for b = 1, self.size do
    local sourceOffset = self.sourceLength - self.sourceSize[b] + 1
    local sourceInput = src[b]
    local sourceInputRev = src[b]:index(1, torch.linspace(self.sourceSize[b], 1, self.sourceSize[b]):long())

    -- Source input is left padded [PPPPPPABCDE] .
    self.sourceInput[{{sourceOffset, self.sourceLength}, b}]:copy(sourceInput)
    self.sourceInputPadLeft = true

    -- Rev source input is right padded [EDCBAPPPPPP] .
    self.sourceInputRev[{{1, self.sourceSize[b]}, b}]:copy(sourceInputRev)
    self.sourceInputRevPadLeft = false

    for i = 1, #self.sourceInputFeatures do
      local sourceInputFeatures = srcFeatures[b][i]
      local sourceInputRevFeatures = srcFeatures[b][i]:index(1, torch.linspace(self.sourceSize[b], 1, self.sourceSize[b]):long())

      self.sourceInputFeatures[i][{{sourceOffset, self.sourceLength}, b}]:copy(sourceInputFeatures)
      self.sourceInputRevFeatures[i][{{1, self.sourceSize[b]}, b}]:copy(sourceInputRevFeatures)
    end

    if tgt ~= nil then
      -- Input: [<s>ABCDE]
      -- Ouput: [ABCDE</s>]
      local targetLength = tgt[b]:size(1) - 1
      local targetInput = tgt[b]:narrow(1, 1, targetLength)
      local targetOutput = tgt[b]:narrow(1, 2, targetLength)

      -- Target is right padded [<S>ABCDEPPPPPP] .
      self.targetInput[{{1, targetLength}, b}]:copy(targetInput)
      self.targetOutput[{{1, targetLength}, b}]:copy(targetOutput)

      for i = 1, #self.targetInputFeatures do
        local targetInputFeatures = tgtFeatures[b][i]:narrow(1, 1, targetLength)
        local targetOutputFeatures = tgtFeatures[b][i]:narrow(1, 2, targetLength)

        self.targetInputFeatures[i][{{1, targetLength}, b}]:copy(targetInputFeatures)
        self.targetOutputFeatures[i][{{1, targetLength}, b}]:copy(targetOutputFeatures)
      end
    end
  end
end

--[[ Im2Markup: set with a sequence of features
  * features: a tensor of size sequence_length, batch_size, num_hidden
--]]
function Batch:set_encoder(features)
    assert (features:dim() == 3, 'The features tensor should be of size seq_len, batch_size, num_hidden')
    self.size = features:size(2)
    self.sourceLength = features:size(1)
    self.sourceInputFeatures = {}
    self.sourceInputRevReatures = {}
    self.sourceInput = features
    self.sourceInputRev = self.sourceInput:index(1, torch.linspace(self.sourceLength, 1, self.sourceLength):long())
    return self
end
--[[ Im2Markup: set with a sequence of features
  * targetInput: a tensor of size sequence_length, batch_size
  * targetOutput: a tensor of size sequence_length, batch_size
  * contextLength: length of context, scalar
--]]
function Batch:set_decoder(targetInput, targetOutput, contextLength)
    self.targetInput, self.targetOutput = targetInput, targetOutput
    self.sourceLength = contextLength
    self.size = targetInput:size(2)
    self.totalSize = self.size
    self.targetLength = targetInput:size(1)
    self.targetInputFeatures = {}
    self.targetOutputFeatures = {}
    return self
end
function Batch:getSourceInput(t)
  -- If a regular input, return word id, otherwise a table with features.
  if #self.sourceInputFeatures > 0 then
    local inputs = {self.sourceInput[t]}
    for j = 1, #self.sourceInputFeatures do
      table.insert(inputs, self.sourceInputFeatures[j][t])
    end
    return inputs
  else
    return self.sourceInput[t]
  end
end

function Batch:getTargetInput(t)
  -- If a regular input, return word id, otherwise a table with features.
  if #self.targetInputFeatures > 0 then
    local inputs = {self.targetInput[t]}
    for j = 1, #self.targetInputFeatures do
      table.insert(inputs, self.targetInputFeatures[j][t])
    end
    return inputs
  else
    return self.targetInput[t]
  end
end

function Batch:getTargetOutput(t)
  -- If a regular input, return word id, otherwise a table with features.
  local outputs = { self.targetOutput[t] }
  for j = 1, #self.targetOutputFeatures do
    table.insert(outputs, self.targetOutputFeatures[j][t])
  end
  return outputs
end

return Batch
