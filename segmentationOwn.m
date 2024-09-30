% Define directories for images and labels
imageDir = fullfile('data_for_moodle', 'data_for_moodle', 'images_256');
labelDir = fullfile('data_for_moodle', 'data_for_moodle', 'labels_256');

% Get image and annotation files
imageFiles = dir(fullfile(imageDir, '*.jpg'));
annotationFiles = dir(fullfile(labelDir, '*.png'));

% Initialize lists for storing annotated images
annotatedImages = {};
filteredAnnotationFiles = {};

% Extract only the base filenames for matching
annotationNames = {annotationFiles.name};
annotationNames = regexprep(annotationNames, '.png', '');

for i = 1:numel(imageFiles)
    % Get the base name of the image file (without extension)
    [~, baseName, ~] = fileparts(imageFiles(i).name);
    
    % Check if there is a corresponding annotation file
    if ismember(baseName, annotationNames)
        % Add the image file to the list of annotated images
        annotatedImages{end+1} = fullfile(imageDir, imageFiles(i).name);

        % Add the annotation file to the list of filtered annotations
        filteredAnnotationFiles{end+1} = fullfile(labelDir, [baseName, '.png']);
    end
end

% Display the number of annotated images found
fprintf('Found %d annotated images\n', numel(annotatedImages));

splitRatio = 0.8;
rng('default'); % For reproducibility
indices = randperm(numel(annotatedImages));
numTrain = round(splitRatio * numel(indices));
trainIndices = indices(1:numTrain);
testIndices = indices(numTrain+1:end);

% Create a pixelLabelDatastore for the filtered annotations
classes = ["background", "flower"];
labelIDs = [3, 1]; % 3 for 'background', 1 for 'flower'

% Create an imageDatastore for the images
imdsTrain = imageDatastore(annotatedImages(trainIndices));
pxdsTrain = pixelLabelDatastore(filteredAnnotationFiles(trainIndices), classes, labelIDs);

imdsTest = imageDatastore(annotatedImages(testIndices));
pxdsTest = pixelLabelDatastore(filteredAnnotationFiles(testIndices), classes, labelIDs);


% Combine image and pixel label datastores
trainingData = pixelLabelImageDatastore(imdsTrain, pxdsTrain);
testingData = pixelLabelImageDatastore(imdsTest, pxdsTest);


imageSize = [256, 256, 3];  
numClasses = 2;  % Background and flower
numFilters = 64;
filterSize = 3;

layers = [
    % Downsampling (Encoder) Path
    imageInputLayer([256 256 3]) 
    convolution2dLayer(filterSize, numFilters, 'Padding', 'same')
    batchNormalizationLayer
    reluLayer
    convolution2dLayer(filterSize, numFilters, 'Padding', 'same')
    batchNormalizationLayer
    reluLayer
    maxPooling2dLayer(2, 'Stride', 2)

    convolution2dLayer(filterSize, numFilters*2, 'Padding', 'same')
    batchNormalizationLayer
    reluLayer
    convolution2dLayer(filterSize, numFilters*2, 'Padding', 'same')
    batchNormalizationLayer
    reluLayer
    maxPooling2dLayer(2, 'Stride', 2)

    convolution2dLayer(filterSize, numFilters*4, 'Padding', 'same')
    batchNormalizationLayer
    reluLayer
    convolution2dLayer(filterSize, numFilters*4, 'Padding', 'same')
    batchNormalizationLayer
    reluLayer

    % Upsampling (Decoder) Path
    transposedConv2dLayer(2, numFilters*2, 'Stride', 2)
    convolution2dLayer(filterSize, numFilters*2, 'Padding', 'same')
    batchNormalizationLayer
    reluLayer
    convolution2dLayer(filterSize, numFilters*2, 'Padding', 'same')
    batchNormalizationLayer
    reluLayer

    transposedConv2dLayer(2, numFilters, 'Stride', 2)
    convolution2dLayer(filterSize, numFilters, 'Padding', 'same')
    batchNormalizationLayer
    reluLayer
    convolution2dLayer(filterSize, numFilters, 'Padding', 'same')
    batchNormalizationLayer
    reluLayer

    % Final Layers
    convolution2dLayer(1, numClasses)
    softmaxLayer
    pixelClassificationLayer
];

% Set Training Options
options = trainingOptions('adam', ...  
    'InitialLearnRate', 1e-3, ...
    'MaxEpochs', 1, ...
    'MiniBatchSize', 16, ...
    'Shuffle', 'every-epoch', ...
    'VerboseFrequency', 2, ...
    'Plots', 'training-progress');

net = trainNetwork(trainingData, layers, options);
save('mynet.mat', 'net')

% Evaluate the model
pxdsResults = semanticseg(testingData, net, 'WriteLocation', tempdir, 'Verbose', false);

% Compute metrics
metrics = evaluateSemanticSegmentation(pxdsResults, pxdsTest, 'Verbose', true);

% Display the results
fprintf('Class-wise IoU:\n');
disp(metrics.DataSetMetrics)

fprintf('Image-wise IoU:\n');
disp(metrics.ImageMetrics)