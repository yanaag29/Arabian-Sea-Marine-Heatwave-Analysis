% MARINE HEATWAVE ANALYSIS MODEL 2021-2025
% FIXED VERSION - All loading, averaging, plotting, and text visibility issues resolved

clear all
close all
clc

disp('========== MARINE HEATWAVE ANALYSIS MODEL: 2021-2025 ==========')
disp(' ')

years_to_analyze = [2021, 2022, 2023, 2024, 2025];
base_folder = 'C:\YANA\ONEANOGRAPHY\Project_1_Marine_Heatwaves\';

lon_min = 40;
lon_max = 80;
lat_min = 0;
lat_max = 30;

heatwave_threshold = 0.5;

all_sst_data   = [];
all_anom_data  = [];
all_time_dates = [];
lat = [];
lon = [];

disp(['Base folder: ' base_folder])
disp(['Years: ' num2str(years_to_analyze(1)) ' to ' num2str(years_to_analyze(end))])
disp(['Study region: ' num2str(lon_min) '-' num2str(lon_max) 'E, ' num2str(lat_min) '-' num2str(lat_max) 'N'])
disp(' ')

%% ========== LOAD DATA ==========
disp('========== LOADING DATA ==========')
disp(' ')

total_files_loaded = 0;

for yr = years_to_analyze

    disp(['--- Year ' num2str(yr) ' ---'])

    % Collect all files across all 12 month subfolders
    all_year_files  = [];
    months_found    = 0;

    for mo = 1:12
        month_folder = [base_folder num2str(yr) '\' num2str(mo) '\'];

        if ~isfolder(month_folder)
            continue
        end

        cd(month_folder)
        mo_files = dir('*.nc');

        if isempty(mo_files)
            continue
        end

        % Add full path to each file struct
        for k = 1:length(mo_files)
            mo_files(k).folder = month_folder;
        end

        all_year_files = [all_year_files; mo_files];
        months_found   = months_found + 1;
    end

    num_files = length(all_year_files);

    if num_files == 0
        disp(['  WARNING: No files found in any month folder for year ' num2str(yr)])
        continue
    end

    disp(['  Months found: ' num2str(months_found) '  |  Total files: ' num2str(num_files)])
    disp(['  First file: ' all_year_files(1).name])
    disp(['  Last file:  ' all_year_files(end).name])

    % Establish grid from very first valid file
    if isempty(lat)
        cd(all_year_files(1).folder)
        lat = ncread(all_year_files(1).name, 'lat');
        lon = ncread(all_year_files(1).name, 'lon');
        disp(['  Grid established: ' num2str(length(lon)) ' lon x ' num2str(length(lat)) ' lat'])
    end

    year_sst   = zeros(length(lon), length(lat), num_files);
    year_anom  = zeros(length(lon), length(lat), num_files);
    year_dates = NaT(num_files, 1);

    load_errors = 0;

    for i = 1:num_files
        filename  = all_year_files(i).name;
        file_folder = all_year_files(i).folder;
        cd(file_folder)

        % Read SST and anomaly
        try
            year_sst(:,:,i)  = ncread(filename, 'sst');
            year_anom(:,:,i) = ncread(filename, 'anom');
        catch ME
            disp(['  ERROR reading ' filename ': ' ME.message])
            year_sst(:,:,i)  = NaN;
            year_anom(:,:,i) = NaN;
            load_errors = load_errors + 1;
        end

        % Filename: oisst-avhrr-v02r01.YYYYMMDD.nc
        % Date is after the last dot in the stem
        [~, fname_only, ~] = fileparts(filename);
        dot_pos = strfind(fname_only, '.');
        if ~isempty(dot_pos)
            date_str = fname_only(dot_pos(end)+1 : end);
        else
            date_str = '';
        end

        try
            year_num  = str2double(date_str(1:4));
            month_num = str2double(date_str(5:6));
            day_num   = str2double(date_str(7:8));

            if isnan(year_num) || isnan(month_num) || isnan(day_num) || ...
               month_num < 1 || month_num > 12 || day_num < 1 || day_num > 31
                error('Invalid date values parsed')
            end

            year_dates(i) = datetime(year_num, month_num, day_num);
        catch
            disp(['  WARNING: Could not parse date from: ' filename])
            year_dates(i) = NaT;
        end

        total_files_loaded = total_files_loaded + 1;
    end

    % Remove any entries with failed date parsing
    bad_dates = isnat(year_dates);
    if any(bad_dates)
        disp(['  Removing ' num2str(sum(bad_dates)) ' entries with unparseable dates'])
        good_idx   = ~bad_dates;
        year_sst   = year_sst(:,:,good_idx);
        year_anom  = year_anom(:,:,good_idx);
        year_dates = year_dates(good_idx);
    end

    disp(['  Valid days loaded: ' num2str(length(year_dates))])

    if load_errors > 0
        disp(['  ' num2str(load_errors) ' file(s) had read errors (set to NaN)'])
    end

    % Sort by date to ensure chronological order
    [year_dates, sort_idx] = sort(year_dates);
    year_sst  = year_sst(:,:,sort_idx);
    year_anom = year_anom(:,:,sort_idx);

    all_sst_data   = cat(3, all_sst_data, year_sst);
    all_anom_data  = cat(3, all_anom_data, year_anom);
    all_time_dates = [all_time_dates; year_dates];

    disp(['  Successfully appended ' num2str(length(year_dates)) ' days for year ' num2str(yr)])
end

total_days = length(all_time_dates);
disp(' ')
disp(['Total files loaded: ' num2str(total_files_loaded)])
disp(['Total days in dataset: ' num2str(total_days)])
disp(' ')

if total_days == 0
    error('No data loaded. Check folder paths and filename format.')
end

%% ========== DATA QUALITY CONTROL ==========
disp('========== DATA QUALITY CONTROL ==========')

all_sst_data(all_sst_data > 1000)   = NaN;
all_anom_data(all_anom_data > 1000) = NaN;
all_sst_data(all_sst_data < -2)     = NaN;

sst_valid   = sum(~isnan(all_sst_data(:)));
sst_quality = (sst_valid / numel(all_sst_data)) * 100;

disp(['SST data quality: ' num2str(sst_quality, '%.1f') '% valid'])
disp(' ')

%% ========== GEOGRAPHIC SUBSETTING ==========
disp('========== GEOGRAPHIC SUBSETTING ==========')

lon_idx = find(lon >= lon_min & lon <= lon_max);
lat_idx = find(lat >= lat_min & lat <= lat_max);

if isempty(lon_idx) || isempty(lat_idx)
    error('No grid points found in specified lon/lat range. Check coordinate values.')
end

regional_sst  = all_sst_data(lon_idx, lat_idx, :);
regional_anom = all_anom_data(lon_idx, lat_idx, :);

disp(['Region: ' num2str(length(lon_idx)) ' lon x ' num2str(length(lat_idx)) ' lat grid points'])
disp(' ')

%% ========== SPATIAL AVERAGING ==========
disp('========== CALCULATING DAILY AVERAGES ==========')

regional_avg_sst  = squeeze(mean(regional_sst,  [1 2], 'omitnan'));
regional_avg_anom = squeeze(mean(regional_anom, [1 2], 'omitnan'));

regional_avg_sst  = regional_avg_sst(:);
regional_avg_anom = regional_avg_anom(:);

disp(['Daily averages calculated for ' num2str(total_days) ' days'])
disp(' ')

%% ========== OVERALL STATISTICS ==========
disp('========== OVERALL STATISTICS ==========')
disp(' ')

sst_mean   = mean(regional_avg_sst,   'omitnan');
sst_median = median(regional_avg_sst, 'omitnan');
sst_std    = std(regional_avg_sst,    'omitnan');
sst_min    = min(regional_avg_sst);
sst_max    = max(regional_avg_sst);

anom_mean   = mean(regional_avg_anom,   'omitnan');
anom_median = median(regional_avg_anom, 'omitnan');
anom_std    = std(regional_avg_anom,    'omitnan');
anom_min    = min(regional_avg_anom);
anom_max    = max(regional_avg_anom);

disp('Sea Surface Temperature (C):')
disp(['  Mean:    ' num2str(sst_mean,   '%.2f')])
disp(['  Median:  ' num2str(sst_median, '%.2f')])
disp(['  Std Dev: ' num2str(sst_std,    '%.2f')])
disp(['  Min:     ' num2str(sst_min,    '%.2f')])
disp(['  Max:     ' num2str(sst_max,    '%.2f')])
disp(' ')

disp('Temperature Anomaly (C):')
disp(['  Mean:    ' num2str(anom_mean,   '%.2f')])
disp(['  Median:  ' num2str(anom_median, '%.2f')])
disp(['  Std Dev: ' num2str(anom_std,    '%.2f')])
disp(['  Min:     ' num2str(anom_min,    '%.2f')])
disp(['  Max:     ' num2str(anom_max,    '%.2f')])
disp(' ')

%% ========== HEATWAVE DETECTION ==========
disp('========== HEATWAVE DETECTION ==========')
disp(' ')

heatwave_idx        = regional_avg_anom > heatwave_threshold;
total_heatwave_days = sum(heatwave_idx);
percent_heatwave    = (total_heatwave_days / total_days) * 100;

disp(['Threshold: > ' num2str(heatwave_threshold) 'C anomaly'])
disp(['Heatwave days: ' num2str(total_heatwave_days) ' / ' num2str(total_days)])
disp(['Percentage:    ' num2str(percent_heatwave, '%.1f') '%'])
disp(' ')

%% ========== ANNUAL BREAKDOWN ==========
disp('========== ANNUAL STATISTICS ==========')
disp(' ')

annual_yr         = [];
annual_days_count = [];
annual_sst_mean   = [];
annual_anom_mean  = [];
annual_hw_days    = [];
annual_hw_pct     = [];

year_extracted = year(all_time_dates);

for yr = years_to_analyze
    year_mask = (year_extracted == yr);

    if sum(year_mask) == 0
        disp(['Year ' num2str(yr) ': No data found'])
        continue
    end

    yr_sst  = regional_avg_sst(year_mask);
    yr_anom = regional_avg_anom(year_mask);
    yr_hw   = heatwave_idx(year_mask);

    yr_sst_mean   = mean(yr_sst,  'omitnan');
    yr_sst_max    = max(yr_sst);
    yr_anom_mean  = mean(yr_anom, 'omitnan');
    yr_hw_count   = sum(yr_hw);
    yr_hw_percent = (yr_hw_count / sum(year_mask)) * 100;

    disp(['Year ' num2str(yr) ':'])
    disp(['  Days: '          num2str(sum(year_mask))])
    disp(['  Mean SST: '      num2str(yr_sst_mean,  '%.2f') 'C  (max: ' num2str(yr_sst_max, '%.2f') 'C)'])
    disp(['  Mean Anomaly: '  num2str(yr_anom_mean, '%.2f') 'C'])
    disp(['  Heatwave days: ' num2str(yr_hw_count)  ' (' num2str(yr_hw_percent, '%.1f') '%)'])
    disp(' ')

    annual_yr         = [annual_yr;        yr];
    annual_days_count = [annual_days_count; sum(year_mask)];
    annual_sst_mean   = [annual_sst_mean;   yr_sst_mean];
    annual_anom_mean  = [annual_anom_mean;  yr_anom_mean];
    annual_hw_days    = [annual_hw_days;    yr_hw_count];
    annual_hw_pct     = [annual_hw_pct;     yr_hw_percent];
end

%% ========== SEASONAL ANALYSIS ==========
disp('========== SEASONAL ANALYSIS ==========')
disp(' ')

months_data  = month(all_time_dates);
month_names  = {'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};
month_abbrev = {'J','F','M','A','M','J','J','A','S','O','N','D'};

seasonal_mon       = [];
seasonal_sst_mean  = [];
seasonal_anom_mean = [];
seasonal_hw_pct    = [];

for m = 1:12
    month_mask = (months_data == m);

    if sum(month_mask) == 0
        continue
    end

    mon_sst  = regional_avg_sst(month_mask);
    mon_anom = regional_avg_anom(month_mask);
    mon_hw   = heatwave_idx(month_mask);

    mon_sst_mean   = mean(mon_sst,  'omitnan');
    mon_anom_mean  = mean(mon_anom, 'omitnan');
    mon_hw_percent = (sum(mon_hw) / sum(month_mask)) * 100;

    msg = sprintf('%s: SST=%.2fC, Anom=%.2fC, HW=%.1f%%', ...
                  month_names{m}, mon_sst_mean, mon_anom_mean, mon_hw_percent);
    disp(msg)

    seasonal_mon       = [seasonal_mon;       m];
    seasonal_sst_mean  = [seasonal_sst_mean;  mon_sst_mean];
    seasonal_anom_mean = [seasonal_anom_mean; mon_anom_mean];
    seasonal_hw_pct    = [seasonal_hw_pct;    mon_hw_percent];
end
disp(' ')

%% ========== TREND ANALYSIS ==========
disp('========== TREND ANALYSIS ==========')
disp(' ')

time_vector = (1:total_days)';

valid_sst  = ~isnan(regional_avg_sst);
coeffs_sst = polyfit(time_vector(valid_sst), regional_avg_sst(valid_sst), 1);
sst_trend_per_year = coeffs_sst(1) * 365;

valid_anom  = ~isnan(regional_avg_anom);
coeffs_anom = polyfit(time_vector(valid_anom), regional_avg_anom(valid_anom), 1);
anom_trend_per_year = coeffs_anom(1) * 365;

sst_fit       = polyval(coeffs_sst, time_vector(valid_sst));
sst_ss_res    = sum((regional_avg_sst(valid_sst) - sst_fit).^2);
sst_ss_tot    = sum((regional_avg_sst(valid_sst) - mean(regional_avg_sst(valid_sst))).^2);
sst_r_squared = 1 - (sst_ss_res / sst_ss_tot);

sst_trend_str  = sprintf('%+.4f', sst_trend_per_year);
anom_trend_str = sprintf('%+.4f', anom_trend_per_year);
r_squared_str  = sprintf('%.4f',  sst_r_squared);

disp(['SST trend:     ' sst_trend_str  'C per year  (R^2 = ' r_squared_str ')'])
disp(['Anomaly trend: ' anom_trend_str 'C per year'])
disp(' ')



%% ========== VISUALIZATIONS ==========
disp('========== CREATING VISUALIZATIONS ==========')

% Close any existing figures first
close all
pause(0.5)

% ----------------------------------------------------------------
% Plot 1: SST Time Series  (standalone figure, then capture)
% ----------------------------------------------------------------
fig = figure('Position',[50 50 1600 1000],'Color','white','Visible','on');

subplot(3,2,1)
sst_trend_line = polyval(coeffs_sst, time_vector);
p1a = plot(all_time_dates, regional_avg_sst, 'b-', 'LineWidth', 0.8);
hold on
p1b = plot(all_time_dates, sst_trend_line, 'r--', 'LineWidth', 2.5);
hold off
grid on
set(gca,'XColor','black','YColor','black','Color',[0.95 0.95 0.95],'FontSize',10)
title('Sea Surface Temperature Time Series','FontSize',11,'FontWeight','bold','Color','black')
xlabel('Date','FontSize',10,'Color','black')
ylabel('Temperature (C)','FontSize',10,'Color','black')
ylim([sst_min-0.5, sst_max+0.5])
xlim([min(all_time_dates) max(all_time_dates)])
lg1=legend([p1a p1b],{'Daily SST',sprintf('Trend: %s C/yr',sst_trend_str)},'Location','northwest','FontSize',9);
set(lg1,'TextColor','black','Color','white','EdgeColor',[0.3 0.3 0.3],'Box','on')
drawnow

% ----------------------------------------------------------------
% Plot 2: Anomaly with Heatwave Events
% ----------------------------------------------------------------
subplot(3,2,2)
anom_trend_line = polyval(coeffs_anom, time_vector);
p2a = plot(all_time_dates, regional_avg_anom, 'Color',[0.5 0.5 0.5],'LineWidth',0.8);
hold on
hw_dates = all_time_dates(heatwave_idx);
hw_anom  = regional_avg_anom(heatwave_idx);
p2b = scatter(hw_dates, hw_anom, 8, 'r', 'filled');
p2c = plot(all_time_dates, anom_trend_line, 'b--','LineWidth',2.5);
thr_x = [min(all_time_dates) max(all_time_dates)];
thr_y = [heatwave_threshold heatwave_threshold];
p2d = plot(thr_x, thr_y, 'k--','LineWidth',1.5);
hold off
grid on
set(gca,'XColor','black','YColor','black','Color',[0.95 0.95 0.95],'FontSize',10)
title('Temperature Anomaly with Heatwave Events','FontSize',11,'FontWeight','bold','Color','black')
xlabel('Date','FontSize',10,'Color','black')
ylabel('Anomaly (C)','FontSize',10,'Color','black')
xlim([min(all_time_dates) max(all_time_dates)])
lg2=legend([p2a p2b p2c p2d],{'Daily Anomaly','Heatwave Events',...
    sprintf('Trend: %s C/yr',anom_trend_str),...
    sprintf('Threshold %.1fC',heatwave_threshold)},...
    'Location','southwest','FontSize',8);
set(lg2,'TextColor','black','Color','white','EdgeColor',[0.3 0.3 0.3],'Box','on')
drawnow

% ----------------------------------------------------------------
% Plot 3: Annual Heatwave Bar Chart
% ----------------------------------------------------------------
subplot(3,2,3)
b3 = bar(annual_yr, annual_hw_pct, 0.6, 'FaceColor',[0.85 0.2 0.2]);
hold on
mx = [annual_yr(1)-0.6, annual_yr(end)+0.6];
my = [percent_heatwave, percent_heatwave];
p3m = plot(mx, my, 'b--','LineWidth',2);
for i = 1:length(annual_yr)
    text(annual_yr(i), annual_hw_pct(i)+2.5, sprintf('%.1f%%',annual_hw_pct(i)),...
        'HorizontalAlignment','center','FontSize',9,'FontWeight','bold','Color','black')
end
hold off
grid on
set(gca,'XColor','black','YColor','black','Color',[0.95 0.95 0.95],...
    'FontSize',10,'XTick',annual_yr)
xlabel('Year','FontSize',10,'Color','black')
ylabel('Heatwave Days (%)','FontSize',10,'Color','black')
title('Annual Heatwave Days Percentage','FontSize',11,'FontWeight','bold','Color','black')
ylim([0 115])
xlim([annual_yr(1)-0.7, annual_yr(end)+0.7])
lg3=legend([b3 p3m],{'Heatwave Days %',sprintf('Mean: %.1f%%',percent_heatwave)},...
    'Location','northeast','FontSize',9);
set(lg3,'TextColor','black','Color','white','EdgeColor',[0.3 0.3 0.3],'Box','on')
drawnow

% ----------------------------------------------------------------
% Plot 4: SST Distribution  (use bar instead of histogram)
% ----------------------------------------------------------------
subplot(3,2,4)
sst_valid_data = regional_avg_sst(~isnan(regional_avg_sst));
[counts, edges] = histcounts(sst_valid_data, 30);
centers = (edges(1:end-1) + edges(2:end)) / 2;
b4 = bar(centers, counts, 1, 'FaceColor',[0.2 0.6 0.9],'FaceAlpha',0.8,'EdgeColor','none');
hold on
ymax4 = max(counts) * 1.15;
p4a = plot([sst_mean   sst_mean],   [0 ymax4], 'r-','LineWidth',2.5);
p4b = plot([sst_median sst_median], [0 ymax4], 'g-','LineWidth',2.5);
hold off
grid on
set(gca,'XColor','black','YColor','black','Color',[0.95 0.95 0.95],'FontSize',10)
xlabel('Temperature (C)','FontSize',10,'Color','black')
ylabel('Frequency (days)','FontSize',10,'Color','black')
title('SST Distribution','FontSize',11,'FontWeight','bold','Color','black')
ylim([0 ymax4])
lg4=legend([b4 p4a p4b],{'SST distribution',...
    sprintf('Mean: %.2fC',sst_mean),...
    sprintf('Median: %.2fC',sst_median)},...
    'Location','northeast','FontSize',9);
set(lg4,'TextColor','black','Color','white','EdgeColor',[0.3 0.3 0.3],'Box','on')
drawnow

% ----------------------------------------------------------------
% Plot 5: Seasonal Pattern  (two separate lines, NO yyaxis)
% ----------------------------------------------------------------
subplot(3,2,5)
% Normalize heatwave % to SST scale for overlay
sst_lo  = min(seasonal_sst_mean) - 1;
sst_hi  = max(seasonal_sst_mean) + 1;
hw_lo   = 0;
hw_hi   = max(seasonal_hw_pct) * 1.2 + 1;
% Scale hw to sst range for display
hw_scaled = sst_lo + (seasonal_hw_pct - hw_lo) ./ (hw_hi - hw_lo) .* (sst_hi - sst_lo);

p5a = plot(seasonal_mon, seasonal_sst_mean, 'b-o','LineWidth',2,'MarkerSize',7,'MarkerFaceColor','b');
hold on
p5b = plot(seasonal_mon, hw_scaled, 'r-s','LineWidth',2,'MarkerSize',7,'MarkerFaceColor','red');
hold off
grid on
set(gca,'XColor','black','YColor','black','Color',[0.95 0.95 0.95],...
    'FontSize',10,'XTick',1:12,...
    'XTickLabel',{'J','F','M','A','M','J','J','A','S','O','N','D'})
xlim([0.5 12.5])
ylim([sst_lo sst_hi])
xlabel('Month','FontSize',10,'Color','black')
ylabel('Mean SST (C)  /  Heatwave % (scaled)','FontSize',9,'Color','black')
title('Seasonal Pattern','FontSize',11,'FontWeight','bold','Color','black')
lg5=legend([p5a p5b],{'Mean SST (C)','Heatwave % (scaled)'},...
    'Location','north','FontSize',9);
set(lg5,'TextColor','black','Color','white','EdgeColor',[0.3 0.3 0.3],'Box','on')

% Add heatwave % tick labels on right side manually
ax5 = gca;
hw_ticks_pct = linspace(hw_lo, hw_hi, 5);
hw_ticks_scaled = sst_lo + (hw_ticks_pct - hw_lo)./(hw_hi-hw_lo).*(sst_hi-sst_lo);
for ti = 1:length(hw_ticks_pct)
    text(ax5, 12.6, hw_ticks_scaled(ti), sprintf('%.0f%%',hw_ticks_pct(ti)),...
        'FontSize',8,'Color','red','HorizontalAlignment','left',...
        'Clipping','off')
end
drawnow

% ----------------------------------------------------------------
% Plot 6: Summary Statistics Box
% ----------------------------------------------------------------
subplot(3,2,6)
axis off

stats_text = sprintf([...
    'Arabian Sea Heatwave Model\n'...
    '(2021-2025)\n\n'...
    'Period:          %d days (%.1f yrs)\n'...
    'Mean SST:        %.2f C (sd %.2f)\n'...
    'Mean Anomaly:    %.2f C (sd %.2f)\n\n'...
    'Heatwave Days:   %d  (%.1f%%)\n'...
    'SST Trend:       %s C/year\n'...
    'Anom Trend:      %s C/year\n'...
    'R-squared:       %s\n\n'...
    'Study Area:      40-80E, 0-30N\n'...
    'Resolution:      0.25 deg\n'...
    'Data Quality:    %.1f%% valid'],...
    total_days, total_days/365,...
    sst_mean, sst_std,...
    anom_mean, anom_std,...
    total_heatwave_days, percent_heatwave,...
    sst_trend_str, anom_trend_str, r_squared_str,...
    sst_quality);

text(0.05, 0.95, stats_text,...
    'FontSize',10,'FontName','Monospaced',...
    'VerticalAlignment','top','HorizontalAlignment','left',...
    'BackgroundColor',[0.85 0.85 0.85],'EdgeColor','black',...
    'Margin',10,'Color','black','FontWeight','bold',...
    'Units','normalized')
drawnow

% ----------------------------------------------------------------
% Super title
% ----------------------------------------------------------------
sg = sgtitle('Arabian Sea Marine Heatwave Analysis Model: 2021-2025',...
    'FontSize',13,'FontWeight','bold');
set(sg,'Color','black')

drawnow
pause(1)

% Reset groot
set(groot,'DefaultAxesXColor','remove')
set(groot,'DefaultAxesYColor','remove')
set(groot,'DefaultTextColor','remove')
set(groot,'DefaultAxesColor','remove')
set(groot,'DefaultAxesFontSize','remove')

disp('Visualizations created successfully!')
disp(' ')

%% ========== SAVE RESULTS ==========
disp('========== SAVING RESULTS ==========')
disp(' ')

print(fig, 'heatwave_model_2021_2025_complete.png', '-dpng', '-r300')
disp('SUCCESS: Figure saved - heatwave_model_2021_2025_complete.png')

daily_results = table(all_time_dates, regional_avg_sst, regional_avg_anom, heatwave_idx, ...
    'VariableNames', {'Date', 'SST_C', 'Anomaly_C', 'Heatwave_Flag'});
writetable(daily_results, 'daily_heatwave_data_2021_2025.csv')
disp('SUCCESS: Daily data saved - daily_heatwave_data_2021_2025.csv')

annual_data = table(annual_yr, annual_days_count, annual_sst_mean, annual_anom_mean, annual_hw_days, annual_hw_pct, ...
    'VariableNames', {'Year','Days','Mean_SST','Mean_Anomaly','Heatwave_Days','Heatwave_Percent'});
writetable(annual_data, 'annual_heatwave_summary_2021_2025.csv')
disp('SUCCESS: Annual summary saved - annual_heatwave_summary_2021_2025.csv')

seasonal_data = table(seasonal_mon, seasonal_sst_mean, seasonal_anom_mean, seasonal_hw_pct, ...
    'VariableNames', {'Month','Mean_SST','Mean_Anomaly','Heatwave_Percent'});
writetable(seasonal_data, 'seasonal_heatwave_summary_2021_2025.csv')
disp('SUCCESS: Seasonal summary saved - seasonal_heatwave_summary_2021_2025.csv')

disp(' ')

%% ========== FINAL SUMMARY ==========
disp('========== ANALYSIS COMPLETE ==========')
disp(' ')
disp(['Period:            ' num2str(years_to_analyze(1)) '-' num2str(years_to_analyze(end)) ' (' num2str(total_days) ' days)'])
disp(['Files processed:   ' num2str(total_files_loaded)])
disp(['Data quality:      ' num2str(sst_quality, '%.1f') '%'])
disp(['Heatwave days:     ' num2str(total_heatwave_days) ' (' num2str(percent_heatwave, '%.1f') '%)'])
disp(['Temperature trend: ' sst_trend_str 'C per year'])
disp(['R-squared:         ' r_squared_str])
disp(' ')
disp('4 output files created:')
disp('  1. heatwave_model_2021_2025_complete.png')
disp('  2. daily_heatwave_data_2021_2025.csv')
disp('  3. annual_heatwave_summary_2021_2025.csv')
disp('  4. seasonal_heatwave_summary_2021_2025.csv')
disp(' ')
disp('PROJECT 1 COMPLETE')
disp(' ')