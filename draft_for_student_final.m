close all
clear all
% Load workspace
load('base_WS_v6.mat')

%% STEP 1: Connection to database
% Add the InfluxDB library
addpath(genpath('./influxdb-client'));
% Init client
URL = 'DatabaseIP';
USER = '';
PASS = '';
DATABASE = 'DatabaseName';
influxdb = InfluxDB(URL, USER, PASS, DATABASE);
% Test the connection
[ok, millis] = influxdb.ping();
assert(ok, 'InfluxDB is DOWN!');
fprintf('InfluxDB is OK (%.2fms)\n\n', millis);

%% STEP 2: Read data from database
str = 'SELECT * FROM MeasurementName WHERE Configuration';
result_query = influxdb.runQuery(str);
query = result_query.series('MeasurementName');
TSP = query.time;
data = query.table();
% Assign one variable to each column 
signal_1 = [data.rms];
signal_2 = [data.mean];
signal_3 = [data.skewness];
signal_4 = [data.kurtosis];
data_imported = [signal_1 signal_2 signal_3 signal_4];
m = length(signal_1);
% This line below will only be useful if you want to skip STEP 3
new_data = data_imported;

%% STEP 3: Check if there is data that has not been processed yet
% Search if any of the data imported matches the last data that was read in
% the previous execution of the script.
index = 0;
for i = 1:m
   % Search for a sample in the data_imported that is equal to te last data
   % that was read in the previous query.
   if(data_imported(i,:) == last_data_read)
        index = i;
   end
end
% If the same data sample is found, then we only want to keep the newer
% data as that has not been processed.
if (index ~= 0)
    new_data = data_imported(index:m,:);
    n2 = length(new_data(:,1));
else % If not, all data is considered unprocessed and index will remain 0
    new_data = data_imported;
    n2 = length(data_imported(:,1));
end
% Store the last data input that will be processed this time, which is the
% last data found in "new_data". So the same operation can be performed
% next time the script is ran.
last_data_read = new_data(n2,:);
% Overwrite the .mat file that contains this piece of data.
filename = 'base_WS_v6';
save(filename,'last_data_read','model','net','PCA_matrix');

%% STEP 4: PCA data processing
% PCA matrix can be found in the WS
% / -----------------------------------------------------
% WRITE YOUR CODE HERE
% / -----------------------------------------------------

%% STEP 5: Novelty detection
% model can be found in the WS
[labels,scores] = predict(model,PCA_result);
% Plot and boundary: Known datapoints (blue) and unknown datapoints (red)
figure,
xlim([2.5 5])
ylim([-0.5 0.5])
title('Novelty detection')
xlabel('PC1')
ylabel('PC2')
set(gca,'Color','w')
legend('off')
hold on
for cont = 1:length(PCA_result(:,1))
   if labels{cont} == ('1')
    color = [0 0 1] ;
    plot(PCA_result(cont,1),PCA_result(cont,2),'Marker','.','LineStyle','none','Color',color,'MarkerSize',20);
    hold on
   elseif labels{cont} == ('0')
    color = [1 0 0];
    plot(PCA_result(cont,1),PCA_result(cont,2),'Marker','*','LineStyle','none','Color',color,'MarkerSize',20);
    hold on
   end
end
% Data is separated in two vectors, one for known data other for unknown
% data
Test_samples_known = zeros(1,2);
Test_samples_unknown = zeros(1,2);
index_known = 1;
index_unknown = 1;
for cont = 1:length(labels)
    if labels{cont} == ('1')
        Test_samples_known(index_known,:) = PCA_result(cont,:);
        index_known = index_known + 1;
    else
        Test_samples_unknown(index_unknown,:) = PCA_result(cont,:);
        index_unknown = index_unknown + 1;
    end
end

%% STEP 6: Diagnostic (Only to known data)
% Create a vector that covers the region that is to be plotted
x = 2.5:0.01:5;
y = -0.5:0.01:0.5;
[X, Y] = meshgrid(x,y);
X = X(:);
Y = Y(:);
grid = [X Y];
size_grid = size(grid);
grid = grid';
% Previously trained neural network classifies the grid values
% net can be found in the WS
nn_class = net(grid);
y1 = nn_class;
y2 = round(y1');
for i=1:1:size(y2,1)
    if y2(i,1)==1
        Z(i,1)=1;
    elseif y2(i,2)==1
        Z(i,2)=2;
    end
end
% Neural network returns the probablity that each input data belongs to one
% class or the other
nn_class2 = net(Test_samples_known');
prob_class = round(100*nn_class2');
% Plot for diagnostic
[foo , classD] = max(Z');
classD = classD';
colors = ['b.'; 'r.'];
figure,
hold on
for j = 1:2
  thisX = X(classD == j);
  thisY = Y(classD == j);
  plot(thisX, thisY, colors(j,:));
  % Insert xlim and ylim so same region so plotted region is always the
  % same
end
for j=1:size(Test_samples_known(:,1))
  plot(Test_samples_known(j,1),Test_samples_known(j,2),'.','LineWidth',0.5,'MarkerEdgeColor','g','MarkerSize',10);
  % Insert xlim and ylim so same region so plotted region is always the
  % same
end
xlabel('PC1','FontSize',11);
ylabel('PC2','FontSize',11);
title('Status Diagnosis Training')

%% STEP 7: Writing Test_samples_known
% Prepare the data
for z=1:length(Test_samples_known)
result_post = Series('MeasurementName')...
 . fields('Field_1_Name', Test_samples_known(z,1)) ...
 . fields('Field_2_Name', Test_samples_known(z,2)) ...
 . fields('Field_3_Name', prob_class(z,1)) ...
 . fields('Field_4_Name', prob_class(z,2));
% Build preview
influxdb.writer() ...
 .append(result_post)...
 .build()
% Post
influxdb.writer() ...
 .append(result_post)...
 .execute();
end

%% STEP 8: Writing Test_samples_unknown to a separate measurement in the database
% Prepare the data
for z=1:length(Test_samples_unknown)
result_post = Series('MeasurementName')...
 . fields('Field_1_Name', Test_samples_unknown(z,1)) ...
 . fields('Field_2_Name', Test_samples_unknown(z,2));
% Build preview
influxdb.writer() ...
 .append(result_post)...
 .build()
% Post
influxdb.writer() ...
 .append(result_post)...
 .execute();
end