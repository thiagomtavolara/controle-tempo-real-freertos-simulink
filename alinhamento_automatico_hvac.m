function [op,ok,mensagem]=alinhamento_automatico_hvac(sim,real,modo)
% ALINHAMENTO_AUTOMATICO_HVAC Procura eventos correspondentes do comando.
%
% Uso: [op, ok, mensagem] = alinhamento_automatico_hvac(sim, real, modo)
% sim.u: comando simulado em Structure With Time.
% real: matriz [tempo_s referencia temperatura controle].
% modo: 0 para malha aberta. Outros modos retornam ok=false.
% Retorna os instantes zero em op e ok=true quando encontra uma sequencia
% compativel de niveis e duracoes. Nao utiliza a temperatura para alinhar.
%
% Se a deteccao falhar ou for ambigua, o chamador decide como prosseguir.
% comparar_simulacao_planta usa o inicio dos registros nessa situacao.
% Algumas mensagens desta rotina mencionam alinhamento manual; elas nao
% significam que a interface atual ofereca uma janela para esse ajuste.
%
% Autor: Thiago Miorando Tavolara
% TCC em Engenharia de Controle e Automacao - UFRGS
% Orientacao: Prof. Marcelo Gotz
op=struct('zero_real',0,'zero_sim',0,'offset_temperatura',0, ...
    'metodo_alinhamento','manual','observacao_alinhamento','');
ok=false; mensagem='Alinhamento manual: evento automatico nao identificado.';
if modo~=0
    mensagem='Malha fechada: escolha o mesmo evento na referencia.'; return;
end
try
    ts=sim.u.time(:); us=sim.u.signals.values(:);
    tr=real(:,1); ur=real(:,4);
    if numel(ts)~=numel(us) || numel(ts)<3 || any(diff(ts)<0) || ...
            any(~isfinite([ts;us;tr;ur])) || any(diff(tr)<=0)
        mensagem='Comandos ou tempos invalidos para deteccao automatica.'; return;
    end
    [ts,ii]=unique(ts,'last'); us=us(ii);
    % Tolerancia de amplitude proporcional ao comando; nao e tolerancia termica.
    tol=max(1e-6,1e-3*max(abs([us;ur])));
    [sr,vr,br]=patamares(tr,ur,tol);
    [ss,vs,bs]=patamares(ts,us,tol);
    if ~br || ~bs || numel(vr)<2
        mensagem='Comando sem patamares estaveis suficientes; escolha o evento manualmente.'; return;
    end
    % Eventos medidos: transicoes reais. Uma amostra inicial nao e um degrau.
    er=(2:numel(vr))'; es=(2:numel(vs))';
    % Excecao explicita: simulacao inicia em t=0 com comando nao nulo.
    % Assume degrau a partir de zero; exige transicao posterior para conferir.
    if abs(ts(1))<1e-9 && abs(vs(1))>tol && numel(vs)>=2
        es=[1;es];
    end
    pares=[]; tlim=max(2,5*max(median(diff(tr)),median(diff(ts))));
    for ir=er'
        for is=es'
            antesS=0; if is>1, antesS=vs(is-1); end
            if abs(vr(ir-1)-antesS)>tol || abs(vr(ir)-vs(is))>tol, continue; end
            % Exige que a sequencia restante de comandos coincida.
            nr=numel(vr)-ir; ns=numel(vs)-is;
            if nr~=ns, continue; end
            if any(abs(vr(ir:end)-vs(is:end))>tol), continue; end
            if nr>0 && any(abs((tr(sr(ir+1:end))-tr(sr(ir)))- ...
                    (ts(ss(is+1:end))-ts(ss(is))))>tlim), continue; end
            pares(end+1,:)=[ir is];
        end
    end
    % Pares de varias bordas podem representar o mesmo deslocamento.
    if isempty(pares)
        mensagem='Nenhum degrau com niveis e duracoes correspondentes. Use alinhamento manual.'; return;
    end
    desloc=tr(sr(pares(:,1)))-ts(ss(pares(:,2)));
    if max(desloc)-min(desloc)>tlim
        mensagem='Mais de um alinhamento plausivel. Escolha o evento manualmente.'; return;
    end
    % Usa o evento mais cedo, preservando a resposta desde o acionamento.
    [~,j]=min(tr(sr(pares(:,1)))); ir=pares(j,1); is=pares(j,2);
    op.zero_real=tr(sr(ir)); op.zero_sim=ts(ss(is));
    op.metodo_alinhamento='automatico_comando_MA';
    mensagem=sprintf('Automatico MA: mesmo degrau do comando. Real %.3f s; simulacao %.3f s.', ...
        op.zero_real,op.zero_sim);
    if is==1
        mensagem=[mensagem ' Simulacao inicia em t=0 com comando aplicado; assumido degrau a partir de zero, conferido pela transicao seguinte.'];
    end
    op.observacao_alinhamento=mensagem; ok=true;
catch erro
    mensagem=['Deteccao automatica indisponivel: ' erro.message];
end
end

% Exige ao menos tres amostras e 0.4 s de duracao em cada patamar estavel.
function [ini,niveis,ok]=patamares(t,v,tol)
ini=[1;find(abs(diff(v))>tol)+1]; fim=[ini(2:end)-1;numel(v)];
niveis=zeros(numel(ini),1); ok=true;
for j=1:numel(ini)
    trecho=v(ini(j):fim(j)); niveis(j)=median(trecho);
    if numel(trecho)<3 || t(fim(j))-t(ini(j))<0.4 || ...
            max(abs(trecho-niveis(j)))>tol
        ok=false; return;
    end
end
end
