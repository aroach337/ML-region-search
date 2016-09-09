(:
Copyright 2016 MarkLogic Corporation 

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
:)

import module namespace geojson = "http://marklogic.com/geospatial/geojson" at "/MarkLogic/geospatial/geojson.xqy";
declare namespace foo = "http://marklogic.com/foo";
declare option xdmp:coordinate-system "wgs84";

let $input := xdmp:get-request-body()

let $region := fn:string($input/region)
let $operation := fn:string($input/operation)

let $idx := cts:geospatial-region-path-reference("//foo:region")
let $qry := cts:geospatial-region-query($idx,$operation,$region,("units=meters"))
let $res := cts:search(doc(), $qry)//foo:region/data()

let $regions :=
for $r in $res
return object-node { "feature" : object-node { "type":"Feature", "geometry": geojson:to-geojson(cts:region($r)) } }

return object-node {
  "results" : array-node { $regions }
}
