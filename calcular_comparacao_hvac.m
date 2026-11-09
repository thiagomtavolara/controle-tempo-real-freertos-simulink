function r=calcular_comparacao_hvac(sim,real,op)
% CALCULAR_COMPARACAO_HVAC Calcula a diferenca entre temperatura real e simulada.
%
% Uso: r = calcular_comparacao_hvac(sim, real, op)
% sim: estrutura com ref, temp e u, cada sinal em Structure With Time.
% real: matriz [tempo_s referencia temperatura controle].
% op: campos zero_real e zero_sim em segundos, e offset_temperatura em C.
%
% Usa apenas o intervalo comum. Interpola temperatura linearmente e mantem
% referencia/comando por retencao de ordem zero, sem extrapolacao.
% Retorna curvas, RMSE, MAE, erro maximo absoluto e vies. O erro e definido
% como temperatura real menos simulada; as medias sao calculadas por amostra.
% Recebe o alinhamento do chamador, sem procurar deslocamentos para reduzir erro.
%
% Autor: Thiago Miorando Tavolara
% TCC em Engenharia de Controle e Automacao - UFRGS
% Orientacao: Prof. Marcelo Gotz
if size(real,2)~=4 || size(real,1)<2 || any(~isfinite(real(:))) || any(diff(real(:,1))<=0)
    error('Ensaio real: esperado tempo crescente e quatro colunas finitas.');
end
if any(~isfinite([op.zero_real op.zero_sim op.offset_temperatura]))
    error('Alinhamento e offset devem ser finitos.');
end
[tr,vr]=lerSinal(sim.ref); [ty,vy]=lerSinal(sim.temp); [tu,vu]=lerSinal(sim.u);
tr=tr-op.zero_sim; ty=ty-op.zero_sim; tu=tu-op.zero_sim;
vy=vy+op.offset_temperatura;
treal=real(:,1)-op.zero_real;
% A intersecao temporal evita comparar amostras sem correspondente simulado.
inicio=max([treal(1),tr(1),ty(1),tu(1)]);
fim=min([treal(end),tr(end),ty(end),tu(end)]);
if fim<=inicio, error('Nao ha intervalo comum apos o alinhamento.'); end
sel=treal>=inicio & treal<=fim;
t=treal(sel);
if numel(t)<2, error('Menos de duas medicoes no intervalo comum.'); end
ys=interp1(ty,vy,t,'linear');
rs=reter(tr,vr,t); us=reter(tu,vu,t);
yr=real(sel,3); rr=real(sel,2); ur=real(sel,4);
% Vies positivo indica temperatura real maior que a simulada, em media.
e=yr-ys;
r=struct('tempo',t,'temp_real',yr,'temp_sim',ys,'ref_real',rr,'ref_sim',rs, ...
    'u_real',ur,'u_sim',us,'erro',e,'opcoes',op, ...
    'rmse',sqrt(mean(e.^2)),'mae',mean(abs(e)), ...
    'erro_max',max(abs(e)),'vies',mean(e), ...
    'diferenca_referencia_max',max(abs(rr-rs)), ...
    'n_amostras',numel(t),'intervalo',[t(1) t(end)]);
r.metodo='Temperatura: interpolacao linear. Referencia/comando: retencao de ordem zero. Sem extrapolacao. Metricas por amostra.';
end

function [t,v]=lerSinal(s)
if ~isstruct(s) || ~isfield(s,'time') || ~isfield(s,'signals') || ...
        numel(s.signals)~=1 || ~isfield(s.signals,'values')
    error('Sinal simulado deve ter time e signals.values.');
end
t=s.time(:); v=s.signals.values;
if ~isvector(v) || numel(t)~=numel(v) || numel(t)<2
    error('Sinal simulado deve ser escalar e ter ao menos duas amostras.');
end
v=v(:);
if any(~isfinite(t)) || any(~isfinite(v)) || any(diff(t)<0)
    error('Sinal simulado contem dados invalidos ou tempo decrescente.');
end
% Em tempos duplicados, preserva a ultima amostra, apos a atualizacao.
[t,idx]=unique(t,'last'); v=v(idx);
if numel(t)<2, error('Sinal simulado sem duracao.'); end
end

% Mantem o valor da ultima amostra ate a proxima atualizacao do sinal.
function vq=reter(t,v,q)
[~,idx]=histc(q,t);
if any(idx<1), error('Retencao solicitada fora do intervalo do sinal.'); end
vq=v(idx);
end
