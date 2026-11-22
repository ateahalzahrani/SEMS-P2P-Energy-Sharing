function T = export_hourly_logs()
%EXPORT_HOURLY_LOGS  Hourly Simulink logs for the manuscript cases
%   Case 1 - proposed SEMS, non-uniform initial SOC [0.3 0.6 0.9]
%   Case 2 - proposed SEMS, uniform low initial SOC  [0.2 0.2 0.2]
%   plus a no-sharing baseline (P_exchange_i = 0) for each case (Table 6).
% Runs on TEMPORARY COPIES of Energy_Management_Model1.slx in tempdir; the
% original model and your base-workspace variables are never changed.
% Output (this folder): Hourly_Logs_Case1_Case2.xlsx + one CSV per run.

here = fileparts(mfilename('fullpath'));
src  = fullfile(here,'Energy_Management_Model1.slx');
if ~evalin('base','exist(''G'',''var'')')
    evalin('base',['run(''' fullfile(here,'setup_parameters.m') ''')']);
end
td = fullfile(tempdir,'emm_hourly'); if ~exist(td,'dir'), mkdir(td); end
old = cd(td); restore = onCleanup(@() cd(old)); %#ok<NASGU>

%        sheet name          model copy   SOC_init        sharing
runs = {'Case1_Proposed',   'EMM_sh',    [0.3 0.6 0.9],  true;
        'Case2_Proposed',   'EMM_sh',    [0.2 0.2 0.2],  true;
        'Case1_NoSharing',  'EMM_ns',    [0.3 0.6 0.9],  false;
        'Case2_NoSharing',  'EMM_ns',    [0.2 0.2 0.2],  false};
qty  = {'P_PV','P_load','P_bat','P_exchange','surplus','deficit','SOC'};
outx = fullfile(here,'Hourly_Logs_Case1_Case2.xlsx');
if exist(outx,'file'), delete(outx); end

prepare(src,td,'EMM_sh',true);
prepare(src,td,'EMM_ns',false);

T = cell(1,size(runs,1));
for r = 1:size(runs,1)
    in = Simulink.SimulationInput(runs{r,2});
    in = in.setVariable('SOC_init',runs{r,3});
    in = in.setModelParameter('SignalLogging','on','SignalLoggingName','lg', ...
        'UnconnectedOutputMsg','none','ReturnWorkspaceOutputs','on');
    S = sim(in); L = S.lg;
    t  = L.getElement('P_PV_1').Values.Time(:);
    Tc = table(t/3600,'VariableNames',{'Hour'});
    for q = 1:numel(qty)
        for k = 1:3
            n = sprintf('%s_%d',qty{q},k); Tc.(n) = val(L,n,t);
        end
    end
    Pg = val(L,'P_grid',t);
    Tc.P_grid_net     = Pg;              % model sign: + export, - import
    Tc.Grid_import    = max(-Pg,0);
    Tc.Grid_export    = max(Pg,0);
    Tc.Sum_deficit    = Tc.deficit_1 + Tc.deficit_2 + Tc.deficit_3;
    Tc.Sum_surplus    = Tc.surplus_1 + Tc.surplus_2 + Tc.surplus_3;
    Tc.Sum_P_exchange = Tc.P_exchange_1 + Tc.P_exchange_2 + Tc.P_exchange_3;
    writetable(Tc,outx,'Sheet',runs{r,1});
    writetable(Tc,fullfile(here,['Hourly_' runs{r,1} '.csv']));
    T{r} = Tc;
end
close_system('EMM_sh',0); close_system('EMM_ns',0);

% ---- daily summary (hours 0-23, dt = 1 h) ----
lo = evalin('base','SOC_low'); hi = evalin('base','SOC_high');
mn = evalin('base','SOC_min'); mx = evalin('base','SOC_max');
names = {'Initial SOC';'PV energy (kWh)';'Load energy (kWh)'; ...
    'Grid import (kWh)';'Grid export (kWh)'; ...
    'Self-consumption ratio SCR = 1 - E_export/E_PV';'Grid dependency index GDI = E_import/E_load'; ...
    'Battery charge, sum P_bat>0 (kWh)';'Battery discharge, sum |P_bat<0| (kWh)'; ...
    'Energy through P_exchange, sum |P_ex| (kWh)';'Net sum of P_exchange (kWh)'; ...
    'Average SOC B1';'Average SOC B2';'Average SOC B3'; ...
    sprintf('SOC samples outside [%.2f, %.2f] (of 75)',mn,mx); ...
    sprintf('SOC samples at %.2f (depleted) (of 75)',mn); ...
    sprintf('SOC samples outside [%.2f, %.2f] (of 75)',lo,hi)};
V = cell(numel(names),size(runs,1));
for r = 1:size(runs,1)
    X = T{r}(1:24,:); Y = T{r};
    PV = [X.P_PV_1 X.P_PV_2 X.P_PV_3]; LD = [X.P_load_1 X.P_load_2 X.P_load_3];
    PB = [X.P_bat_1 X.P_bat_2 X.P_bat_3]; PE = [X.P_exchange_1 X.P_exchange_2 X.P_exchange_3];
    SOC = [Y.SOC_1 Y.SOC_2 Y.SOC_3];
    Epv = sum(PV(:)); Eld = sum(LD(:)); Ei = sum(X.Grid_import); Ee = sum(X.Grid_export);
    V(:,r) = {mat2str(runs{r,3}); Epv; Eld; Ei; Ee; 1-Ee/Epv; Ei/Eld; ...
        sum(PB(PB>0)); -sum(PB(PB<0)); sum(abs(PE(:))); sum(PE(:)); ...
        mean(SOC(:,1)); mean(SOC(:,2)); mean(SOC(:,3)); ...
        nnz(SOC<mn-1e-6 | SOC>mx+1e-6); nnz(abs(SOC-mn)<1e-6); nnz(SOC<lo | SOC>hi)};
end
Sm = cell2table([names V],'VariableNames',[{'Metric'} runs(:,1)']);
writetable(Sm,outx,'Sheet','Summary');

notes = {
 'Source model: Energy_Management_Model1.slx with setup_parameters.m (run on temporary copies; original untouched).'
 'Case definitions taken from the manuscript (Optimal P2P Energy Sharing ... Hierarchical Control Algorithm, Jan 2026): Case 1 SOC_init = [0.3 0.6 0.9]; Case 2 SOC_init = [0.2 0.2 0.2]. Only SOC_init differs between the cases.'
 'Proposed = model as built (P_exchange_i from Central_Controller). NoSharing = same model with each building''s P_exchange input tied to 0 (baseline for Table 6).'
 'Solver: fixed-step ode4, Ts = 3600 s, 0-86400 s. Row "Hour h" = value at the start of hour h (25 rows, 0-24). Daily totals use hours 0-23.'
 'Units: powers in kW (one row = 1 h, so a row value is also kWh); SOC in p.u.'
 'P_grid_net uses the model sign: positive = export, negative = import. Grid_import = max(-P_grid,0); Grid_export = max(P_grid,0).'
 'P_exchange_i = value applied at building i input (positive adds to building i, negative removes from it).'
 'PARAMETER MISMATCH: model PV gain = eta*A/1000 = 0.18*150/1000, i.e. 27 kW peak per building at G = 1000 W/m2; the manuscript (Table 1, Sec. results) states 15 kW peak and ~44.99 kW peak export.'
 'MODEL NOTE 1: SOC integrates (Ts/C_bat)*(P_PV - P_load + P_bat + P_exchange); P_bat is added on top of P_PV - P_load and the gain Ts/C_bat (=360 /s) drives SOC to its limits within one step.'
 'MODEL NOTE 2: Central_Controller does not conserve P_exchange (sum over buildings is not zero) and P_grid = total surplus - total deficit ignores P_exchange.'
 'MODEL NOTE 3: Repeating Sequence for G has period 82800 s (23 h), so hour 23 repeats G(1) and G(24) is never used.'};
writecell(notes,outx,'Sheet','Notes');
fprintf('Saved %s\n',outx);
disp(Sm);
end

function prepare(src,td,nm,share)
if bdIsLoaded(nm), close_system(nm,0); end
f = fullfile(td,[nm '.slx']); copyfile(src,f,'f'); load_system(f);
for k = 1:3
    b  = sprintf('%s/Building_%d',nm,k);
    pb = get_param(b,'PortHandles');
    if ~share
        ln = get_param(pb.Inport(1),'Line'); if ln ~= -1, delete_line(ln); end
        p = get_param(b,'Position');
        add_block('simulink/Sources/Constant',sprintf('%s/Zero_%d',nm,k),'Value','0', ...
            'SampleTime','Ts','Position',[p(1)-150 p(2)+20 p(1)-120 p(2)+40]);
        add_line(nm,sprintf('Zero_%d/1',k),sprintf('Building_%d/1',k));
    end
    ln = get_param(pb.Inport(1),'Line');
    logp(get_param(ln,'SrcPortHandle'),sprintf('P_exchange_%d',k));
    op = find_system(b,'SearchDepth',1,'BlockType','Outport');
    for j = 1:numel(op)
        logp(pb.Outport(str2double(get_param(op{j},'Port'))),sprintf('%s_%d',get_param(op{j},'Name'),k));
    end
end
cc = [nm '/Central_Controller']; pc = get_param(cc,'PortHandles');
op = find_system(cc,'SearchDepth',1,'BlockType','Outport');
for j = 1:numel(op)
    if strcmp(get_param(op{j},'Name'),'P_grid')
        logp(pc.Outport(str2double(get_param(op{j},'Port'))),'P_grid');
    end
end
end

function logp(ph,name)
set_param(ph,'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',name);
end

function y = val(L,n,t)
v = L.getElement(n).Values; d = squeeze(v.Data); d = double(d(:)); tv = v.Time(:);
if numel(tv) == numel(t) && all(abs(tv - t) < 1e-6)
    y = d;
elseif numel(tv) == 1
    y = repmat(d,numel(t),1);
else
    y = interp1(tv,d,t,'previous','extrap');
end
end
