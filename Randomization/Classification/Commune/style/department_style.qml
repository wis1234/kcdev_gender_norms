<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>
<qgis>
  <renderer-v2 type="singleSymbol">
    <symbol name="0" type="fill">
      <layer class="SimpleFill" locked="0">
        <prop k="color" v="255,200,150,100"/> <!-- couleur douce -->
        <prop k="outline_color" v="100,100,100,255"/>
        <prop k="outline_width" v="0.8"/>
      </layer>
    </symbol>
  </renderer-v2>
  <labeling>
    <rule>
      <label fieldname="NAME_1"/> <!-- champ contenant le nom du département -->
      <font size="12" bold="1"/>
      <buffer size="1" color="255,255,255"/> <!-- halo blanc autour du texte -->
      <placement centroid="1"/>
    </rule>
  </labeling>
</qgis>
