1. can we get better zombie blocks using the csv file? current results.txt has data at end state which isnt that relevant since that is after gc
=> created a new curve

2. how can we use the results to prove the problem exists?
=> f2fs level tracing: software level: biosnoop: on vm: check writes
=> trace f2fs functions

3. hypothesis? waf caused by the db or gc how can we separate them?


6. there is no definite way to prove that our thing works without fdp, how to go about that?
=> f2fs stats f2fs adaptive temp: dirty segment count increment reduce 

7. if we get lucky with fdp we can again perform with and without our code for better results

8. fsync?
=> f2fs handles it

next plan?
1. code changes => FRIDAY, SAT, SUN
2. workloads => run sqlite again, reduce batch size, multiple workloads at the same time(both rocksdb, sqlite)
3. ppt => structure, content, speaker => MONDAY
-> problem, evidence, solutions: multistream, fdp why solution doesnt work on physical, f2fs changes/ heuristics, evaluation, future work

### how to run modified f2fs on vm? f2f2-stable repo
### load kernel from source => FEMU