import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const StockApp()); }
class StockApp extends StatelessWidget {
  const StockApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(debugShowCheckedModeBanner:false,title:'SS OIL Stok Kontrol',theme:ThemeData(colorSchemeSeed:const Color(0xFFD51B23),useMaterial3:true,scaffoldBackgroundColor:const Color(0xFFF6F7F9)),home:const Home());
}
class Product {
  final String code,name,barcode,price,stock;
  const Product(this.code,this.name,this.barcode,this.price,this.stock);
  Map<String,dynamic> toJson()=>{'code':code,'name':name,'barcode':barcode,'price':price,'stock':stock};
  factory Product.fromJson(Map<String,dynamic> j)=>Product('${j['code']??''}','${j['name']??''}','${j['barcode']??''}','${j['price']??''}','${j['stock']??''}');
}
class Home extends StatefulWidget { const Home({super.key}); @override State<Home> createState()=>_HomeState(); }
class _HomeState extends State<Home> {
  // Catalog keys are Artikal IDs, not barcodes. The catalog survives count resets.
  final Map<String,Product> catalog={};
  final Map<String,List<String>> barcodesById={};
  final Map<String,Map<String,String>> barcodeErrors={};
  final Map<String,String> baseStock={};
  String serverUrl='http://192.168.100.50:8765';
  String accessToken='';
  bool sqlBusy=false;

  final Map<String,Map<String,dynamic>> issues={};
  final Map<String,Product> orders={};
  Product? current;
  final count=TextEditingController();
  final search=TextEditingController();
  String status='Ürün listesi yükleyin veya barkod okutun';
  @override void initState(){
    super.initState();
    _load();
  }
  @override void dispose(){
    count.dispose();search.dispose();super.dispose();
  }
  Future<void> _load() async {
    final p=await SharedPreferences.getInstance();
    try {
      final c=jsonDecode(p.getString('catalog')??'[]') as List;
      final i=jsonDecode(p.getString('issues')??'[]') as List;
      final o=jsonDecode(p.getString('orders')??'[]') as List;
      serverUrl=p.getString('sql_server_url')??serverUrl;
      accessToken=p.getString('sql_api_token')??'';
      final bs=jsonDecode(p.getString('base_stock')??'{}') as Map;
      final bm=jsonDecode(p.getString('barcode_map')??'{}') as Map;
      final be=jsonDecode(p.getString('barcode_errors')??'{}') as Map;

      setState((){
        for(final x in c){final a=Product.fromJson(Map<String,dynamic>.from(x));if(a.code.isNotEmpty)catalog[a.code]=a;}
        for(final x in i){final m=Map<String,dynamic>.from(x);issues['${m['code']}']=m;}
        for(final x in o){final a=Product.fromJson(Map<String,dynamic>.from(x));orders[a.code]=a;}
        for(final e in bs.entries){baseStock['${e.key}']='${e.value}';}
        for(final e in bm.entries){barcodesById['${e.key}']=List<String>.from(e.value as List);}
        for(final e in be.entries){barcodeErrors['${e.key}']=Map<String,String>.from(e.value as Map);}

      });
    } catch(_){setState(()=>status='Kayıt okuma hatası');}
  }
  Future<void> _save() async {
    final p=await SharedPreferences.getInstance();
    await p.setString('catalog',jsonEncode(catalog.values.map((x)=>x.toJson()).toList()));
    await p.setString('issues',jsonEncode(issues.values.toList()));
    await p.setString('orders',jsonEncode(orders.values.map((x)=>x.toJson()).toList()));
    await p.setString('base_stock',jsonEncode(baseStock));
    await p.setString('barcode_map',jsonEncode(barcodesById));
    await p.setString('barcode_errors',jsonEncode(barcodeErrors));
    await p.setString('sql_server_url',serverUrl);
    await p.setString('sql_api_token',accessToken);

  }
  void _msg(String s){if(mounted){setState(()=>status=s);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),duration:const Duration(seconds:1)));}}
  Future<Map<String,dynamic>> _api(String route) async {
    final url=Uri.parse('${serverUrl.replaceAll(RegExp(r'/+$'), '')}$route');
    final response=await http.get(url,headers:{'X-SSOIL-Token':accessToken})
        .timeout(const Duration(seconds:15));
    if(response.statusCode!=200)throw Exception('Sunucu HTTP ${response.statusCode}: ${response.body}');
    return Map<String,dynamic>.from(jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }
  String _number(dynamic v)=>v==null?'0':'$v'.replaceAll(',','.');
  Future<void> _sqlSettings() async {
    final host=TextEditingController(text:serverUrl);
    final token=TextEditingController(text:accessToken);
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('SQL bağlantı servisi'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:host,decoration:const InputDecoration(labelText:'Bilgisayar servis adresi')),
        TextField(controller:token,obscureText:true,decoration:const InputDecoration(labelText:'API erişim anahtarı')),
        const SizedBox(height:8),const Text('SQL şifresi telefona girilmez. Bilgisayardaki salt-okunur servis kullanılır.'),
      ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Vazgeç')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Kaydet'))]));
    if(ok==true){serverUrl=host.text.trim();accessToken=token.text.trim();await _save();_msg('Bağlantı ayarları kaydedildi');}
    host.dispose();token.dispose();
  }
  Future<void> _sqlRefresh() async {
    if(sqlBusy)return;
    setState(()=>sqlBusy=true);
    try {
      final result=await _api('/snapshot');
      final products=List<Map<String,dynamic>>.from((result['products'] as List).map((e)=>Map<String,dynamic>.from(e as Map)));
      final nextCatalog=<String,Product>{};
      final nextBase=<String,String>{};
      final nextBarcodes=<String,List<String>>{};
      for(final r in products){
        final id='${r['id']}';
        if(id.isEmpty)continue;
        final bars=List<String>.from((r['barcodes'] as List? ?? []).map((e)=>'$e')).where((e)=>e.isNotEmpty).toSet().toList();
        final old=catalog[id];
        final price=_number(r['price']);
        final stock=_number(r['stock']);
        nextBase[id]=stock;
        nextBarcodes[id]=bars;
        nextCatalog[id]=Product(id,'${r['name']??old?.name??''}',bars.isNotEmpty?bars.first:(old?.barcode??''),price,stock);
      }
      // Merge instead of deleting locally added products and count records.
      catalog.addAll(nextCatalog);
      baseStock.addAll(nextBase);
      barcodesById.addAll(nextBarcodes);
      await _save();
      if(mounted)setState(()=>current=current==null?null:catalog[current!.code]);
      _msg('${nextCatalog.length} ürün ve barkodları güncellendi');
    }catch(e){_msg('Stok güncelleme başarısız: $e');}
    finally{if(mounted)setState(()=>sqlBusy=false);}
  }
  Future<void> _barcodeProblem(String barcode,String reason,{String id=''}) async {
    final idCtrl=TextEditingController(text:id);
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(reason),content:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('Barkod: $barcode'),TextField(controller:idCtrl,keyboardType:TextInputType.number,
          decoration:const InputDecoration(labelText:'Doğru Artikal ID (isteğe bağlı)')),
      ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Vazgeç')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Hata listesine kaydet'))]));
    if(ok==true){barcodeErrors[barcode]={'id':idCtrl.text.trim(),'barcode':barcode,'error':reason};await _save();_msg('Barkod hata listesine kaydedildi');}
    idCtrl.dispose();
  }
  Future<void> _lookupBarcode(String barcode) async {
    final ids=barcodesById.entries.where((e)=>e.value.contains(barcode)).map((e)=>e.key).toList();
    if(ids.isEmpty){await _barcodeProblem(barcode,'Barkod kayıtlı değil');return;}
    String? selected;
    if(ids.length==1){selected=ids.first;}
    else {
      final controller=TextEditingController();
      selected=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Çift ürün – Doğru ID seç'),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          for(final id in ids)ListTile(title:Text('ID $id'),subtitle:Text(catalog[id]?.name??''),onTap:()=>Navigator.pop(ctx,id)),
          TextField(controller:controller,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Artikal ID elle gir')),
        ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('İptal')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text.trim()),child:const Text('ID ile devam'))]));
      controller.dispose();
      if(selected!=null&&selected.isNotEmpty){barcodeErrors[barcode]={'id':selected,'barcode':barcode,'error':'Çift ürün'};await _save();}
    }
    if(selected==null||selected.isEmpty)return;
    if(!catalog.containsKey(selected)){await _barcodeProblem(barcode,'Yanlış barkod',id:selected);return;}
    await _refreshOne(selected);
  }
  Future<void> _refreshOne(String id) async {
    if(sqlBusy)return;
    setState(()=>sqlBusy=true);
    try {
      final result=await _api('/product/${Uri.encodeComponent(id)}');
      final old=catalog[id];
      if(old==null)throw Exception('Önce Stok Güncelle yapın');
      final stock=_number(result['stock']);
      final price=_number(result['price']);
      final updated=Product(id,old.name,old.barcode,price,stock);
      catalog[id]=updated;
      await _save();
      if(mounted)setState((){current=updated;count.clear();});
      _msg('ID $id: güncel stok $stock');
    }catch(e){_msg('Anlık sorgu hatası: $e');}
    finally{if(mounted)setState(()=>sqlBusy=false);}
  }
  Future<void> _scan() async {
    final code=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const ScanPage()));
    if(code==null||!mounted)return;
    await _lookupBarcode(code.trim());
  }
  Future<void> _addManual() async {
    final id=TextEditingController(),name=TextEditingController(),barcode=TextEditingController(),price=TextEditingController(),stock=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('Manuel ürün ekle'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final field in <(TextEditingController,String)>[(id,'Artikal ID'),(name,'Ürün adı'),(barcode,'Barkod'),(price,'Fiyat'),(stock,'Stok')])
          Padding(padding:const EdgeInsets.only(bottom:8),child:TextField(controller:field.$1,decoration:InputDecoration(labelText:field.$2,border:const OutlineInputBorder()))),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Vazgeç')),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Kaydet'))]));
    if(ok==true){
      final code=id.text.trim(),ean=barcode.text.trim();
      if(code.isEmpty||name.text.trim().isEmpty||ean.isEmpty){_msg('ID, isim ve barkod gerekli');}
      else if(catalog.containsKey(code)||catalog.values.any((x)=>x.barcode==ean)){_msg('Bu ID veya barkod zaten kayıtlı');}
      else {catalog[code]=Product(code,name.text.trim(),ean,price.text.trim(),stock.text.trim());await _save();setState((){current=catalog[code];});_msg('Ürün kalıcı olarak kaydedildi');}
    }
    for(final c in [id,name,barcode,price,stock]){c.dispose();}
  }
  Future<void> _editCurrent() async {
    final p=current;if(p==null)return;
    final price=TextEditingController(text:p.price),stock=TextEditingController(text:p.stock);
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text('Stok ve fiyat – ${p.code}'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:price,decoration:const InputDecoration(labelText:'Satış fiyatı')),
        TextField(controller:stock,decoration:const InputDecoration(labelText:'Stok miktarı'))]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Vazgeç')),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Kaydet'))]));
    if(ok==true){final updated=Product(p.code,p.name,p.barcode,price.text.trim(),stock.text.trim());catalog[p.code]=updated;await _save();if(mounted)setState(()=>current=updated);_msg('Fiyat ve stok güncellendi');}
    price.dispose();stock.dispose();
  }
  // Excel/CSV import is update-only. Unknown Artikal IDs are skipped.
  Future<void> _import() async {
    final r=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['xlsx','csv']);
    if(r==null||r.files.single.path==null)return;
    try {
      final file=File(r.files.single.path!);
      List<List<String>> rows=[];
      if(file.path.toLowerCase().endsWith('.xlsx')){
        final book=xl.Excel.decodeBytes(await file.readAsBytes());
        final sheet=book.tables.values.first;
        if(sheet==null)throw Exception('Excel sayfası boş');
        rows=sheet.rows.map((r)=>r.map((c)=>c?.value?.toString()??'').toList()).toList();
      } else {
        final raw=await file.readAsString();
        final delimiter=raw.split('\n').first.contains(';')?';':',';
        rows=CsvToListConverter(fieldDelimiter:delimiter,shouldParseNumbers:false).convert(raw)
          .map((r)=>r.map((x)=>x.toString()).toList()).toList();
      }
      if(rows.length<2)throw Exception('Ürün satırı bulunamadı');
      String norm(String s)=>s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9ğüşöçıа-я]'), '');
      final h=rows.first.map(norm).toList();
      int idx(List<String> opts){for(final x in opts){final i=h.indexOf(norm(x));if(i>=0)return i;}return -1;}
      final ci=idx(['artikal id','artikalid','code','ürün kodu','urun kodu','šifra']);
      final pi=idx(['price','fiyat','cijena','prodajna cijena','satış fiyatı']);
      final si=idx(['stock','stok','stanje','količina','kolicina']);
      if(ci<0 || (pi<0&&si<0))throw Exception('Başlıklar: Artikal ID, Fiyat, Stok');
      String cell(List<String> row,int i)=>i<0||i>=row.length?'':row[i].trim();
      int changed=0,skipped=0;
      for(final row in rows.skip(1)){
        final id=cell(row,ci);final old=catalog[id];
        if(old==null){skipped++;continue;}
        final price=cell(row,pi),stock=cell(row,si);
        if(price.isEmpty&&stock.isEmpty)continue;
        catalog[id]=Product(old.code,old.name,old.barcode,price.isEmpty?old.price:price,stock.isEmpty?old.stock:stock);
        changed++;
      }
      await _save();if(current!=null && mounted){setState(()=>current=catalog[current!.code]);}
      _msg('$changed kayıt güncellendi; $skipped kayıtlı olmayan ID atlandı');
    }catch(e){_msg('Excel aktarım hatası: $e');}
  }
  void _issue(String type) {
    final p=current;if(p==null)return;
    final existing=issues[p.code]??{'code':p.code,'name':p.name,'barcode':p.barcode,'price':p.price,'stock':p.stock,'count':'','types':<String>[]};
    // Always compare against the current single stock value.
    existing['price']=p.price;
    existing['stock']=p.stock;
    final types=List<String>.from(existing['types'] as List);
    if(type=='Eksik'||type=='Fazla'){
      final q=double.tryParse(count.text.replaceAll(',','.'));
      final s=double.tryParse(p.stock.replaceAll(',','.'));
      if(q==null||q<0||s==null){_msg('Geçerli sayılan miktar ve sistem stoku gerekli');return;}
      if(type=='Eksik'&&q>=s || type=='Fazla'&&q<=s){_msg('Sayılan stok ile seçilen durum uyuşmuyor');return;}
      types.remove('Eksik');types.remove('Fazla');existing['count']=count.text;
    }
    if(type=='Sorun Yok'){types.clear();existing['count']='';}else{types.remove('Sorun Yok');}
    if(!types.contains(type))types.add(type);
    existing['types']=types;
    issues[p.code]=existing;
    unawaited(_save());_msg('$type kaydedildi / mevcut kayıt güncellendi');setState((){});
  }
  void _ok(){_issue('Sorun Yok');}
  void _order(){final p=current;if(p==null)return;orders[p.code]=p;unawaited(_save());_msg('Sipariş listesine eklendi / güncellendi');setState((){});}
  Future<void> _export() async {
    try {
      final book=xl.Excel.createExcel();
      final a=book['Stok Kontrol'],b=book['Siparis Listesi'],c=book['Urun Veritabani'],d=book['Manuel Stok'];
      void row(xl.Sheet s,List<String> vals)=>s.appendRow(vals.map((v)=>xl.TextCellValue(v)).toList());
      row(a,['Artikal ID','Ürün Adı','Barkod','Satış Fiyatı','Sistem Stoku','Sayılan Stok','Fark','Sorunlar']);
      for(final m in issues.values){
        final st=double.tryParse('${m['stock']}'.replaceAll(',','.'));
        final co=double.tryParse('${m['count']}'.replaceAll(',','.'));
        final types=List<String>.from(m['types'] as List);
        row(a,['${m['code']}','${m['name']}','${m['barcode']}','${m['price']}','${m['stock']}','${m['count']}',st!=null&&co!=null?'${co-st}':'',types.join(', ')]);
      }
      row(b,['Artikal ID','Ürün Adı','Barkod']);
      for(final p in orders.values){row(b,[p.code,p.name,p.barcode]);}
      row(c,['Artikal ID','Ürün Adı','Barkod','Fiyat','Stok']);
      row(d,['Artikal ID','Fiyat','Stok']);
      for(final p in catalog.values){row(c,[p.code,p.name,p.barcode,p.price,p.stock]);row(d,[p.code,p.price,p.stock]);}
      final e=book['Hatali Barkodlar'];
      row(e,['Artikal ID','Barkod','Hata']);
      for(final r in barcodeErrors.values){row(e,[r['id']??'',r['barcode']??'',r['error']??'']);}
      book.delete('Sheet1');
      final bytes=book.encode();if(bytes==null)throw Exception('Excel oluşturulamadı');
      final now=DateTime.now();
      final stamp='${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_${now.hour}${now.minute.toString().padLeft(2,'0')}';
      final filename='SS_OIL_Stok_$stamp.xlsx';
      // Android system save dialog, not share-only. User selects destination.
      final path=await FilePicker.platform.saveFile(dialogTitle:'Excel dosyasını kaydet',fileName:filename,
        type:FileType.custom,allowedExtensions:['xlsx'],bytes:Uint8List.fromList(bytes));
      if(path==null){_msg('Kaydetme iptal edildi');return;}
      _msg('Excel kaydedildi: $path');
    }catch(e){_msg('Excel kaydetme hatası: $e');}
  }
  Future<void> _clear() async {
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Kayıtları temizle?'),content:const Text('Stok kontrol ve sipariş kayıtları silinir. Önceden dışarı aktarılan Excel dosyaları silinmez. Ürün kataloğu korunur.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Vazgeç')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Temizle'))]));
    if(ok!=true)return;setState((){issues.clear();orders.clear();current=null;count.clear();});await _save();_msg('Yeni kontrol dönemi başladı');
  }
  Future<void> _lists() async {await Navigator.push(context,MaterialPageRoute(builder:(_)=>ListPage(issues:issues,orders:orders,onChanged:() async {await _save();setState((){});})));setState((){});}
  @override
  Widget build(BuildContext context) {
    final p=current;
    return Scaffold(
      appBar:AppBar(
        backgroundColor:Colors.black,
        foregroundColor:Colors.white,
        title:const Text('Stok Kontrol',style:TextStyle(fontWeight:FontWeight.w700)),
        actions:[IconButton(tooltip:'SQL Ayarları',onPressed:_sqlSettings,icon:const Icon(Icons.settings_outlined))],
      ),
      bottomNavigationBar:SafeArea(
        top:false,
        child:Padding(
          padding:const EdgeInsets.fromLTRB(16,8,16,12),
          child:Row(children:[
            Expanded(flex:3,child:FilledButton.icon(
              onPressed:_export,icon:const Icon(Icons.file_download_outlined),label:const Text('Excel’e Aktar'),
              style:FilledButton.styleFrom(minimumSize:const Size(0,52),backgroundColor:const Color(0xFF1E754D)),
            )),
            const SizedBox(width:10),
            Expanded(flex:2,child:OutlinedButton.icon(
              onPressed:_clear,icon:const Icon(Icons.delete_outline),label:const Text('Temizle'),
              style:OutlinedButton.styleFrom(minimumSize:const Size(0,52),foregroundColor:const Color(0xFFB4232C)),
            )),
          ]),
        ),
      ),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        Container(
          decoration:BoxDecoration(color:Colors.black,borderRadius:BorderRadius.circular(18)),
          padding:const EdgeInsets.symmetric(vertical:8,horizontal:20),
          child:Image.asset('assets/ss_oil_logo.jpg',height:112,fit:BoxFit.contain),
        ),
        const SizedBox(height:16),
        Row(children:[
          Expanded(child:FilledButton.icon(
            onPressed:_scan,icon:const Icon(Icons.qr_code_scanner),label:const Text('Barkod Oku'),
            style:FilledButton.styleFrom(minimumSize:const Size(0,56)),
          )),
          const SizedBox(width:10),
          Expanded(child:FilledButton.tonalIcon(
            onPressed:sqlBusy?null:_sqlRefresh,icon:const Icon(Icons.sync),label:const Text('Stok Güncelle'),
            style:FilledButton.styleFrom(minimumSize:const Size(0,56)),
          )),
        ]),
        const SizedBox(height:10),
        OutlinedButton.icon(onPressed:_lists,icon:const Icon(Icons.list_alt),label:Text('Eksik / Fazla ve Sipariş Listesi (${issues.length} / ${orders.length})')),
        const SizedBox(height:10),
        Text(status,style:Theme.of(context).textTheme.bodySmall),
        const SizedBox(height:10),
        TextField(
          controller:search,
          decoration:InputDecoration(
            filled:true,fillColor:Colors.white,border:const OutlineInputBorder(),
            labelText:'Barkod veya ürün kodu',
            suffixIcon:IconButton(icon:const Icon(Icons.search),onPressed:(){
              final v=search.text.trim();
              if(catalog.containsKey(v)){unawaited(_refreshOne(v));}
              else{unawaited(_lookupBarcode(v));}
            }),
          ),
          onSubmitted:(v){
            if(catalog.containsKey(v.trim())){unawaited(_refreshOne(v.trim()));}
            else{unawaited(_lookupBarcode(v.trim()));}
          },
        ),
        const SizedBox(height:12),
        if(p!=null)...[
          Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Kod: ${p.code}'),
              Text(p.name,style:Theme.of(context).textTheme.titleMedium),
              Text('Barkod: ${p.barcode}'),
              Text('Satış: ${p.price} KM     Stok: ${p.stock}',style:Theme.of(context).textTheme.titleSmall),
            ],
          ))),
          const SizedBox(height:12),
          TextField(controller:count,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(border:OutlineInputBorder(),labelText:'Gerçek sayılan stok')),
          const SizedBox(height:8),
          Row(children:[
            Expanded(child:FilledButton.tonal(onPressed:()=>_issue('Eksik'),child:const Text('Eksik'))),
            const SizedBox(width:8),
            Expanded(child:FilledButton.tonal(onPressed:()=>_issue('Fazla'),child:const Text('Fazla'))),
          ]),
          for(final label in ['Yanlış Barkod','Yanlış Fiyat','Etiket Yok'])
            Padding(padding:const EdgeInsets.only(top:8),child:OutlinedButton(onPressed:()=>_issue(label),child:Text(label))),
          const SizedBox(height:10),
          OutlinedButton(onPressed:_ok,child:const Text('Sorun Yok – Kaydet')),
          FilledButton.icon(onPressed:_order,icon:const Icon(Icons.shopping_cart_outlined),label:const Text('Sipariş Listesine Ekle')),
        ]else const Card(child:Padding(padding:EdgeInsets.all(20),child:Text('Ürün seçmek için barkod okutun veya ürün kodunu girin.'))),
        const SizedBox(height:24),
      ]),
    );
  }
}
class ScanPage extends StatefulWidget {const ScanPage({super.key});@override State<ScanPage> createState()=>_ScanPageState();}
class _ScanPageState extends State<ScanPage>{bool done=false;@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Barkod Tara')),body:MobileScanner(onDetect:(capture){if(done)return;final code=capture.barcodes.firstOrNull?.rawValue;if(code==null||code.isEmpty)return;done=true;Navigator.pop(context,code);}));}
class ListPage extends StatefulWidget {final Map<String,Map<String,dynamic>> issues;final Map<String,Product> orders;final Future<void> Function() onChanged;const ListPage({super.key,required this.issues,required this.orders,required this.onChanged});@override State<ListPage> createState()=>_ListPageState();}
class _ListPageState extends State<ListPage>{@override Widget build(BuildContext context)=>DefaultTabController(length:2,child:Scaffold(appBar:AppBar(title:const Text('Kayıt Listeleri'),bottom:const TabBar(tabs:[Tab(text:'Stok / Hatalar'),Tab(text:'Sipariş')])),body:TabBarView(children:[ListView(children:widget.issues.entries.map((e)=>ListTile(title:Text('${e.value['name']}'),subtitle:Text('Kod: ${e.key} • ${e.value['types'].join(', ')} • Sayılan: ${e.value['count']}'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{setState(()=>widget.issues.remove(e.key));await widget.onChanged();}))).toList()),ListView(children:widget.orders.entries.map((e)=>ListTile(title:Text(e.value.name),subtitle:Text('Kod: ${e.value.code} • Barkod: ${e.value.barcode}'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{setState(()=>widget.orders.remove(e.key));await widget.onChanged();}))).toList())])));}
