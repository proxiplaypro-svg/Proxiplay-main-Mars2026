const PDFDocument = require('pdfkit');

// Input is already scoped by game_winner_rows. Never include contact details,
// UID, address or date of birth. The code identifies the specific award.
function partnerRows(entries) {
  return entries.map(({row, prize}) => ({
    winner: [row.prenom, row.nom ? `${row.nom[0]}.` : ''].filter(Boolean).join(' ') || 'Gagnant',
    prize: row.lot_gagne, code: row.code_gagnant,
    status: prize.claimed === true ? 'Remis' : row.statut === 'Expiré' ? 'Expiré' : 'À remettre',
  }));
}

function winnersPdf({gameName, shopName, entries}) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({size:'A4', margin:40, bufferPages:true,
      info:{Title:'ProxiPlay - Remise des lots', Author:'ProxiPlay'}});
    const chunks=[];
    doc.on('data', b=>chunks.push(b)); doc.on('error',reject);
    doc.on('end',()=>resolve(Buffer.concat(chunks)));
    const width=515, cols=[130,165,130,90];
    let y;
    function header() {
      doc.fillColor('#18233B').font('Helvetica-Bold').fontSize(21).text('ProxiPlay | Remise des lots',40,40);
      doc.font('Helvetica').fontSize(11).text(String(shopName||'Partenaire').slice(0,150),40,73,{width});
      doc.fontSize(10).text(String(gameName||'Jeu').slice(0,250),40,doc.y+8,{width});
      doc.fontSize(9).fillColor('#444444').text('Document confidentiel. Vérifier le code dans l’application avant toute remise.\nCocher la liste après remise. En cas de doute, contacter ProxiPlay.',40,doc.y+12,{width});
      y=doc.y+18;
      doc.rect(40,y,width,24).fill('#E9EDF3');
      let x=40;['Gagnant','Lot gagné','Code de retrait','Statut'].forEach((v,i)=>{
        doc.fillColor('#18233B').font('Helvetica-Bold').fontSize(9).text(v,x+6,y+7,{width:cols[i]-12});x+=cols[i];
      }); y+=24;
    }
    header();
    for (const row of partnerRows(entries)) {
      const texts=[row.winner,row.prize,row.code,row.status].map(v=>String(v));
      doc.font('Helvetica').fontSize(9);
      const height=Math.max(40,...texts.map((t,i)=>doc.heightOfString(t,{width:cols[i]-12})+16));
      if(height>590) { reject(Error('Libellé trop long pour le récapitulatif')); doc.end(); return; }
      if(y+height>770){doc.addPage();header();}
      let x=40;
      texts.forEach((t,i)=>{doc.fillColor('#202020').font(i===2?'Helvetica-Bold':'Helvetica').fontSize(9)
        .text(t,x+6,y+8,{width:cols[i]-12});x+=cols[i];});
      doc.strokeColor('#D5DAE1').moveTo(40,y+height).lineTo(555,y+height).stroke(); y+=height;
    }
    const pages=doc.bufferedPageRange();
    for(let p=0;p<pages.count;p++){doc.switchToPage(p);doc.font('Helvetica').fontSize(8).fillColor('#555555')
      // Rester au-dessus de la marge basse : PDFKit cree sinon une page
      // supplementaire lors de l'ecriture du pied de page.
      .text(`ProxiPlay - Liste de remise | ${p+1}/${pages.count}`,40,780,{width,align:'right',lineBreak:false});}
    doc.end();
  });
}
module.exports={partnerRows,winnersPdf};
