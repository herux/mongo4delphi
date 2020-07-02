program Demo;

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces,
  uMainForm in 'uMainForm.pas' {Frm_MainForm},
  uItem in 'uItem.pas' {Frm_Item},
  uFind in 'uFind.pas', m4d_core {Frm_Find};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFrm_MainForm, Frm_MainForm);
  Application.Run;
end.
