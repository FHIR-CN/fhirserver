unit FHIRValueSetChecker;

interface

uses
  SysUtils, Classes,
  AdvObjects, AdvStringObjectMatches,
  FHIRTypes, FHIRComponents, FHIRResources, FHIRUtilities,
  TerminologyServices, TerminologyServerStore;

Type
  TValueSetChecker = class (TAdvObject)
  private
    FStore : TTerminologyServerStore;
    FOthers : TAdvStringObjectMatch; // checkers or code system providers
    fvs : TFHIRValueSet;
    FId: String;
    function check(system, code : String; displays : TStringList) : boolean; overload;
    function findCode(code: String; list : TFhirValueSetDefineConceptList; displays : TStringList): boolean;
    function checkConceptSet(cs: TCodeSystemProvider; cset : TFhirValueSetComposeInclude; code : String; displays : TStringList) : boolean;
    function rule(op : TFhirOperationOutcome; severity : TFhirIssueSeverity; test : boolean; code, msg : string):boolean;
    procedure check(coding: TFhirCoding; op : TFhirOperationOutcome); overload;
    procedure check(code: TFhirCodeableConcept; op : TFhirOperationOutcome); overload;
  public
    constructor Create(store : TTerminologyServerStore; id : String); overload;
    destructor Destroy; override;

    property id : String read FId;

    procedure prepare(vs : TFHIRValueSet);

    function check(system, code : String) : boolean; overload;
    function check(coding : TFhirCoding) : TFhirOperationOutcome; overload;
    function check(coded : TFhirCodeableConcept) : TFhirOperationOutcome; overload;
  end;

implementation

{ TValueSetChecker }

constructor TValueSetChecker.create(store : TTerminologyServerStore; id : string);
begin
  Create;
  FStore := store;
  FId := id;
  FOthers := TAdvStringObjectMatch.create;
  FOthers.PreventDuplicates;
end;

destructor TValueSetChecker.destroy;
begin
  FVs.Free;
  FOthers.Free;
  FStore.Free;
  inherited;
end;

procedure TValueSetChecker.prepare(vs: TFHIRValueSet);
var
  i, j : integer;
  checker : TValueSetChecker;
  cs : TCodeSystemProvider;
  other : TFHIRValueSet;
begin
  FVs := vs.link;
  if fvs.define <> nil then
    FOthers.Add(fvs.define.system, TValueSetProvider.create(FVs.Link));
  if (fvs.compose <> nil) then
  begin
    for i := 0 to fvs.compose.importList.Count - 1 do
    begin
      other := FStore.getValueSetByIdentifier(fvs.compose.importList[i].value);
      try
        if other = nil then
          raise ETerminologyError.create('Unable to find value set '+fvs.compose.importList[i].value);
        checker := TValueSetChecker.create(Fstore.link, other.url);
        try
          checker.prepare(other);
          FOthers.Add(fvs.compose.importList[i].value, checker.Link);
        finally
          checker.free;
        end;
      finally
        other.free;
      end;
    end;
    for i := 0 to fvs.compose.includeList.Count - 1 do
    begin
      if not FOthers.ExistsByKey(fvs.compose.includeList[i].system) then
        FOthers.Add(fvs.compose.includeList[i].system, FStore.getProvider(fvs.compose.includeList[i].system));
      cs := TCodeSystemProvider(FOthers.matches[fvs.compose.includeList[i].system]);
      for j := 0 to fvs.compose.includeList[i].filterList.count - 1 do
        if not (('concept' = fvs.compose.includeList[i].filterList[j].property_) and (fvs.compose.includeList[i].filterList[j].Op = FilterOperatorIsA)) then
          if not cs.doesFilter(fvs.compose.includeList[i].filterList[j].property_, fvs.compose.includeList[i].filterList[j].Op, fvs.compose.includeList[i].filterList[j].value) then
            raise ETerminologyError.create('The filter "'+fvs.compose.includeList[i].filterList[j].property_ +' '+ CODES_TFhirFilterOperator[fvs.compose.includeList[i].filterList[j].Op]+ ' '+fvs.compose.includeList[i].filterList[j].value+'" was not understood in the context of '+cs.system(nil));
    end;
    for i := 0 to fvs.compose.excludeList.Count - 1 do
    begin
      if not FOthers.ExistsByKey(fvs.compose.excludeList[i].system) then
        FOthers.Add(fvs.compose.excludeList[i].system, FStore.getProvider(fvs.compose.excludeList[i].system));
      cs := TCodeSystemProvider(FOthers.matches[fvs.compose.excludeList[i].system]);
      for j := 0 to fvs.compose.excludeList[i].filterList.count - 1 do
        if not (('concept' = fvs.compose.excludeList[i].filterList[j].property_) and (fvs.compose.excludeList[i].filterList[j].Op = FilterOperatorIsA)) then
          if not cs.doesFilter(fvs.compose.excludeList[i].filterList[j].property_, fvs.compose.excludeList[i].filterList[j].Op, fvs.compose.excludeList[i].filterList[j].value) then
            raise Exception.create('The filter "'+fvs.compose.excludeList[i].filterList[j].property_ +' '+ CODES_TFhirFilterOperator[fvs.compose.excludeList[i].filterList[j].Op]+ ' '+fvs.compose.excludeList[i].filterList[j].value+'" was not understood in the context of '+cs.system(nil));
    end;
  end;
end;

function TValueSetChecker.rule(op: TFhirOperationOutcome; severity: TFhirIssueSeverity; test: boolean; code, msg: string): boolean;
var
  issue : TFhirOperationOutcomeIssue;
begin
  result := test;
  if not test then
  begin
    issue := op.issueList.Append;
    issue.severity := severity;
    issue.code := TFhirCodeableConcept.Create;
    with issue.code.codingList.Append do
    begin
      system := 'http://hl7.org/fhir/issue-type';
      code := code;
    end;
    issue.details := msg;
  end;
end;


function TValueSetChecker.findCode(code: String; list : TFhirValueSetDefineConceptList; displays : TStringList): boolean;
var
  i : integer;
begin
  result := false;
  for i := 0 to list.count - 1 do
  begin
    if (code = list[i].code) and not list[i].abstract then
    begin
      result := true;
      displays.Add(list[i].display);
      exit;
    end;
    if findCode(code, list[i].conceptList, displays) then
    begin
      result := true;
      exit;
    end;
  end;
end;

function TValueSetChecker.check(system, code: String): boolean;
var
  list : TStringList;
begin
  list := TStringList.Create;
  try
    result := check(system, code, list);
  finally
    list.Free;
  end;
end;

function TValueSetChecker.check(system, code : String; displays : TStringList) : boolean;
var
  checker : TValueSetChecker;
  cs : TCodeSystemProvider;
  ctxt : TCodeSystemProviderContext;
  i : integer;
begin
  result := false;
  {special case:}
  if (fvs.url = ANY_CODE_VS) then
  begin
    cs := FStore.getProvider(system, true);
    try
      if cs = nil then
        result := false
      else
      begin
        ctxt := cs.locate(code);
        if (ctxt = nil) then
          result := false
        else
          try
            result := true;
            cs.Displays(ctxt, displays);
          finally
            cs.Close(ctxt);
          end;
      end;
    finally
      cs.Free;
    end;
  end
  else
  begin
    if (fvs.define <> nil) and (system = fvs.define.system) then
    begin
      result := FindCode(code, fvs.define.conceptList, displays);
      if result then
        exit;
    end;
    if (fvs.compose <> nil) then
    begin
      for i := 0 to fvs.compose.importList.Count - 1 do
      begin
        if not result then
        begin
          checker := TValueSetChecker(FOthers.matches[fvs.compose.importList[i].value]);
          result := checker.check(system, code, displays);
        end;
      end;
      for i := 0 to fvs.compose.includeList.Count - 1 do
      begin
        if not result then
        begin
          cs := TCodeSystemProvider(FOthers.matches[fvs.compose.includeList[i].system]);
          result := (cs.system(nil) = system) and checkConceptSet(cs, fvs.compose.includeList[i], code, displays);
        end;
      end;
      for i := 0 to fvs.compose.excludeList.Count - 1 do
      begin
        if result then
        begin
          cs := TCodeSystemProvider(FOthers.matches[fvs.compose.excludeList[i].system]);
          result := not ((cs.system(nil) = system) and checkConceptSet(cs, fvs.compose.excludeList[i], code, displays));
        end;
      end;
    end;
  end;
end;

procedure TValueSetChecker.check(coding: TFhirCoding; op : TFhirOperationOutcome);
var
  list : TStringList;
begin
  list := TStringList.Create;
  try
    if rule(op, IssueSeverityError, check(coding.system, coding.code, list), 'code-unknown', 'The system/code "'+coding.system+'"/"'+coding.code+'" is not in the value set') then
      rule(op, IssueSeverityWarning, (coding.display = '') or (list.IndexOf(coding.display) >= 0), 'value', 'The display "'+coding.display+'" is not a valid display for the code');
  finally
    list.Free;
  end;
end;

function TValueSetChecker.check(coding: TFhirCoding): TFhirOperationOutcome;
begin
  result := TFhirOperationOutcome.Create;
  try
    check(coding, result);
    BuildNarrative(result, 'Code Validation');
    result.Link;
  finally
    result.free;
  end;
end;

function TValueSetChecker.check(coded: TFhirCodeableConcept): TFhirOperationOutcome;
begin
  result := TFhirOperationOutcome.Create;
  try
    check(coded, result);
    BuildNarrative(result, 'Code Validation');
    result.Link;
  finally
    result.free;
  end;
end;

procedure TValueSetChecker.check(code: TFhirCodeableConcept; op: TFhirOperationOutcome);
var
  list : TStringList;
  i : integer;
  ok, v : boolean;
  cc, codelist : String;
  prov : TCodeSystemProvider;
  ctxt : TCodeSystemProviderContext;
begin
  list := TStringList.Create;
  try
    ok := false;
    codelist := '';
    for i := 0 to code.codingList.Count - 1 do
    begin
      list.Clear;
      cc := ',{'+code.codingList[i].system+'}'+code.codingList[i].code;
      codelist := codelist + cc;
      v := check(code.codingList[i].system, code.codingList[i].code, list);
      ok := ok or v;
      if (v) then
        rule(op, IssueSeverityWarning, (code.codingList[i].display = '') or (list.IndexOf(code.codingList[i].display) >= 0), 'value', 'The display "'+code.codingList[i].display+'" is not a valid display for the code '+cc)
      else
      begin
        prov := FStore.getProvider(code.codingList[i].system, true);
        try
         if (prov = nil) then
           rule(op, IssueSeverityWarning, false, 'value', 'The system "'+code.codingList[i].system+'" is not known')
         else
         begin
           ctxt := prov.locate(code.codingList[i].code);
           try
             if rule(op, IssueSeverityError, ctxt <> nil, 'value', 'The code "'+code.codingList[i].code+'" is not valid in the system '+code.codingList[i].system) then
             begin
               prov.Displays(ctxt, list);
               rule(op, IssueSeverityWarning, (code.codingList[i].display = '') or (list.IndexOf(code.codingList[i].display) > -1), 'value', 'The display "'+code.codingList[i].display+'" is not a valid display for the code '+cc)
             end;
           finally
             prov.Close(ctxt);
           end;
         end;
        finally
          prov.Free;
        end;
      end;
    end;
    rule(op, IssueSeverityError, ok, 'code-unknown', 'None of the codes provided ('+codelist.Substring(1)+') are in the value set');
  finally
    list.Free;
  end;
end;

Function FreeAsBoolean(cs : TCodeSystemProvider; ctxt : TCodeSystemProviderContext) : boolean; overload;
begin
  result := ctxt <> nil;
  if result then
    cs.Close(ctxt);
end;

Function FreeAsBoolean(cs : TCodeSystemProvider; ctxt : TCodeSystemProviderFilterContext) : boolean; overload;
begin
  result := ctxt <> nil;
  if result then
    cs.Close(ctxt);
end;

function TValueSetChecker.checkConceptSet(cs: TCodeSystemProvider; cset : TFhirValueSetComposeInclude; code: String; displays : TStringList): boolean;
var
  i : integer;
  fc : TFhirValueSetComposeIncludeFilter;
  ctxt : TCodeSystemProviderFilterContext;
  loc :  TCodeSystemProviderContext;
  prep : TCodeSystemProviderFilterPreparationContext;
  filters : Array of TCodeSystemProviderFilterContext;
begin
  result := false;
  if (cset.conceptList.count = 0) and (cset.filterList.count = 0) then
  begin
    loc := cs.locate(code);
    try
      result := loc <> nil;
      if result then
      begin
        cs.displays(loc, displays);
        exit;
      end;
    finally
      cs.Close(loc);
    end;
  end;

  for i := 0 to cset.conceptList.count - 1 do
    if (code = cset.conceptList[i].code) then
    begin
      loc := cs.locate(code);
      if Loc <> nil then
      begin
        cs.close(loc);
        cs.displays(code, displays);
        result := true;
        exit;
      end;
    end;

  if cset.filterList.count > 0 then
  begin
    SetLength(filters, cset.filterList.count);
    prep := cs.getPrepContext;
    try
      for i := 0 to cset.filterList.count - 1 do
      begin
        fc := cset.filterList[i];
        // gg - why? if ('concept' = fc.property_) and (fc.Op = FilterOperatorIsA) then
        filters[i] := cs.filter(fc.property_, fc.Op, fc.value, prep);
      end;
      if cs.prepare(prep) then // all are together, just query the first filter
      begin
        ctxt := filters[0];
        loc := cs.filterLocate(ctxt, code);
        try
          result := loc <> nil;
          if result then
            cs.displays(loc, displays);
        finally
          cs.Close(loc);
        end;
      end
      else
      begin
        for i := 0 to cset.filterList.count - 1 do
        begin
          fc := cset.filterList[i];
          if ('concept' = fc.property_) and (fc.Op = FilterOperatorIsA) then
          begin
            loc := cs.locateIsA(code, fc.value);
            try
              result := loc <> nil;
              if result then
                cs.displays(loc, displays);
            finally
              cs.Close(loc);
            end;
          end
          else
          begin
            ctxt := filters[i];
            loc := cs.filterLocate(ctxt, code);
            try
              result := loc <> nil;
              if result then
                cs.displays(loc, displays);
            finally
              cs.Close(loc);
            end;
          end;
          if result then
            break;
        end;
      end;
    finally
      for i := 0 to cset.filterList.count - 1 do
        cs.Close(filters[i]);
      cs.Close(prep);
    end;
  end;
end;

end.
