import pyarrow.dataset as ds, pyarrow.fs as fs, pyarrow.compute as pc, json, sys
REL = "release/2026-10-21.0"
s3 = fs.S3FileSystem(anonymous=True, region="us-west-2")
lat, lon = -6.933940, -38.457590
xmin, xmax, ymin, ymax = lon-0.0140, lon+0.0140, lat-0.0330, lat+0.0140
def get(theme, typ, cols):
    path = f"overturemaps-us-west-2/{REL}/theme={theme}/type={typ}/"
    dset = ds.dataset(path, filesystem=s3, format="parquet")
    f = (pc.field("bbox", "xmin") < xmax) & (pc.field("bbox", "xmax") > xmin) & (pc.field("bbox", "ymin") < ymax) & (pc.field("bbox", "ymax") > ymin)
    names = set(dset.schema.names)
    t = dset.to_table(filter=f, columns=[c for c in cols if c in names])
    print(theme, typ, t.num_rows, file=sys.stderr)
    return t.to_pylist()
import shapely.wkb
out = {}
for theme, typ, cols in [("transportation","segment",["id","geometry","subtype","class","names","road_surface"]),
                         ("buildings","building",["id","geometry","height","class","names"]),
                         ("places","place",["id","geometry","names","categories","basic_category","taxonomy"]),
                         ("base","water",["id","geometry","subtype","class","names"]),
                         ("base","land_use",["id","geometry","subtype","class"]),
                         ("base","land_cover",["id","geometry","subtype"])]:
    rows = get(theme, typ, cols)
    for r in rows:
        r["geometry"] = shapely.wkb.loads(r["geometry"]).__geo_interface__
    out[typ] = rows
json.dump(out, open("overture_big.json","w"), default=str)
